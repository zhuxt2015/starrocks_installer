#!/bin/bash
###################################################
# 功能: StarRocks 集群安装部署
# 说明:
# 1. 包含启动命令
# 2. 支持重复执行
# 3. 配置文件修改采用非破坏性方式
# 4. 修改FE root密码
###################################################
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"
source "$SCRIPT_DIR/common.sh"

# 检查文件是否已存在
check_file_exists() {
    local host=$1
    local file=$2
    remote_exec "$host" "[ -f $file ]" && return 0 || return 1
}

# 创建必要目录
create_directories() {
    local host=$1
    local service=$2
    local dirs=("${install_path%/}/${service}")
    log_info "Checking and creating directories on $host"

    if [ "$service" == "fe" ]; then
        for key in "${!fe_configs[@]}"; do
            value="${fe_configs[$key]}"
            if [[ -n "$value" ]] && [[ ${key,,} =~ .*_dir$ ]]; then
                dirs+=("${value}")
            fi
        done
    else
        for key in "${!be_configs[@]}"; do
            value="${be_configs[$key]}"
            if [[ -n "$value" ]];then
                if [[ $key =~ .*_dir$ ]]; then
                    dirs+=("${value}")
                # 处理storage_root_path
                elif [[ "$key" == "storage_root_path" ]];then
                    IFS=';' read -ra storage_path <<< "$value"
                    for path in "${storage_path[@]}"; do
                        if [[ "$path" == *","* ]]; then
                            path=$(echo "$path" | cut -d',' -f1)
                        fi
                        dirs+=("$path")
                    done
                fi
            fi
        done
    fi
    for dir in "${dirs[@]}"; do
        log_info "Creating directory $dir on $host"
        local commands=(
            "rm -rf $dir"
            "mkdir -p $dir"
            "chown -R $install_user:$install_user $dir"
            "chmod -R 755 $dir"
        )

        loop_remote_exec "$host" "${commands[@]}"

    done
}

# 解压 StarRocks 包
decompress_package() {
    local host=$1
    local service=$2

    log_info "Decompressing StarRocks package on $host, please wait for about 1 minute"
    local child_dir="StarRocks-${starrocks_version}-centos-amd64"
    local commands=(
        "rm -rf ${install_path%/}/$service"
        "tar -xzf $install_package -C $install_path ${child_dir}/${service}"
        "mv ${install_path%/}/${child_dir}/${service} $install_path"
        "chown -R $install_user:$install_user $install_path"
        "rm -rf ${install_path%/}/$child_dir"
    )
    loop_remote_exec "${host}" "${commands[@]}"
}



create_service() {
    local host=$1
    local service=$2
    local service_name="starrocks_${service}"
    local work_dir="${install_path%/}/${service}"
    local start_script="$work_dir/bin/start_${service}.sh"
    local stop_script="$work_dir/bin/stop_${service}.sh"
    local service_file="/etc/systemd/system/${service_name}.service"

    log_info "Creating systemd service file: $service_file"
    cat <<EOF | remote_exec $host "tee $service_file >/dev/null"
[Unit]
Description=StarRocks ${service_name^} Service
After=network.target

[Service]
Environment=JAVA_HOME=$java_home
User=$install_user
Group=$install_user
WorkingDirectory=$work_dir
ExecStart=$start_script
ExecStop=$stop_script
LimitNOFILE=655350
LimitNPROC=655350
Restart=on-failure
RestartSec=10
StartLimitInterval=180
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

    log_info "$host Reloading systemd daemon..."
    remote_exec "$host" "systemctl daemon-reload"

    log_info "$host Enabling and starting $service_name service..."
    remote_exec "$host" "systemctl enable $service_name"
    remote_exec "$host" "systemctl start $service_name"
    log_info "$host $service_name service setup complete."
}

#分发安装包
distribute_install_file() {
    local host=$1
    local install_package=$2
    log_info "Distribute StarRocks package to $host"
    if ! check_file_exists "$host" "$install_package"; then
        sudo -u "$install_user" scp "$install_package" "$install_user@$host:$install_package"
    fi

}
#将FE和BE加入到集群
add_to_cluster() {
    local host=$1
    local node_type=$2
    log_info "Add $node_type $host to cluster "
    if [ "$host" != "$leader" ] && [ "$node_type" = "fe" ]; then
        mysql -h $leader -uroot -P9030 -e "alter system add FOLLOWER '$host:$edit_log_port'"
    elif [ "$node_type" = "be" ]; then
        mysql -h $leader -uroot -P9030 -e "alter system add BACKEND '$host:$heartbeat_service_port'"
    fi
}
#follower第一次启动
follower_first_start() {
    local host=$1
    if [ "$host" != "$leader" ]; then
        log_info "First start follower on $host"
        cmd="source /etc/profile && sh $install_path/fe/bin/start_fe.sh --helper $leader:$edit_log_port --daemon"
        sudo -u $install_user ssh $install_user@$host "$cmd"
        if check_service_status "$host" "fe";then
            stop_service "$host" "fe"
        fi
    fi

}

# 主函数
main() {
    log_info "Starting StarRocks installation..."

    # 读取配置
    read_hosts_config
    read_config
    read_fe_config
    read_be_config

    if [ ! -f "$install_package" ]; then
        if [ "$online_install" == "false" ];then
            log_error "StarRocks package not found: $install_package"
            exit 1
        else
            log_info "Downloading StarRocks package from ${starrocks_download_url%/}/starrocks-${starrocks_version}-centos-amd64.tar.gz"
            curl -o "$install_package" "${starrocks_download_url%/}/starrocks-${starrocks_version}-centos-amd64.tar.gz"
        fi
    fi

    # 安装从节点 FE
    if [ -n "$leader" ]; then
        local frontend_hosts=()
        frontend_hosts+=("$leader")
        if [ -n "$follower" ];then
            IFS=',' read -ra FOLLOWERS <<< "$follower"
            frontend_hosts+=("${FOLLOWERS[@]}")
        fi
        for frontend_host in "${frontend_hosts[@]}"; do
            log_info "Installing FE on $frontend_host"
            stop_service "$frontend_host" "fe"
            distribute_install_file "$frontend_host" "$install_package"
            create_directories "$frontend_host" "fe"
            decompress_package "$frontend_host" "fe"
            add_to_cluster "$frontend_host" "fe"
            configure_fe "$frontend_host"
            follower_first_start "$frontend_host"
            create_service "$frontend_host" "fe"
            check_service_status "$frontend_host" "fe"
            log_info "Install FE on $frontend_host complete"
        done
    fi

    # 安装 BE 节点
    if [ -n "$backend" ]; then
        IFS=',' read -ra BACKENDS <<< "$backend"
        for backend_host in "${BACKENDS[@]}"; do
            log_info "Installing BE on $backend_host"
            stop_service "$backend_host" "be"
            distribute_install_file "$backend_host" "$install_package"
            create_directories "$backend_host" "be"
            decompress_package "$backend_host" "be"
            add_to_cluster "$backend_host" "be"
            configure_be "$backend_host"
            create_service "$backend_host" "be"
            check_service_status "$backend_host" "be"
            log_info "Install BE on $backend_host complete"
        done
    fi
    # 修改fe root帐号密码
    if [ -n "$fe_root_password" ];then
        log_info "Modifying fe root account password"
        mysql -h "$leader" -uroot -P9030 -e "alter user root identified by '$fe_root_password'"
    fi
    # 打印集群信息
    log_info "StarRocks cluster information:"
    log_info "FE Leader: $leader"
    log_info "FE Followers: $follower"
    log_info "BE Nodes: $backend"


    log_info "StarRocks installation completed successfully"
}

# 执行主函数
main