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

# 主函数
main() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/log.sh"
    source "$SCRIPT_DIR/common.sh"
    # 读取配置
    read_hosts_config
    read_config
    read_fe_config
    read_be_config
    log_info "Starting $starrocks_version StarRocks installation ..."

    #下载安装包
    download_package "$starrocks_version"
    # 安装从节点 FE
    if [ -n "$leader" ]; then
        local frontend_hosts=()
        frontend_hosts+=("$leader")
        if [ -n "$follower" ];then
            if echo "$follower"|grep -qw "$leader";then
                log_error "The leader node cannot be included in the follower node list."
                exit 1
            fi
            IFS=',' read -ra FOLLOWERS <<< "$follower"
            frontend_hosts+=("${FOLLOWERS[@]}")
        fi
        for frontend_host in "${frontend_hosts[@]}"; do
            log_info "Installing FE on $frontend_host"
            stop_service "$frontend_host" "fe"
            distribute_install_file "$frontend_host"
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
            distribute_install_file "$backend_host"
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
        mysql --connect_timeout=5 -h "$leader" -uroot -P9030 -Ne "alter user root identified by '$fe_root_password'"
    fi
    # 打印集群信息
    log_info "StarRocks cluster information:"
    if [ -n "$fe_root_password" ];then
        mysql --connect_timeout=5 -h "$leader" -uroot -P9030 -p${fe_root_password} -e "show frontends;show backends;"
    else
        mysql --connect_timeout=5 -h "$leader" -uroot -P9030 -e "show frontends;show backends;"
    fi

    log_info "StarRocks installation completed successfully"
}

# 执行主函数
main