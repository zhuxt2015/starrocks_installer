#!/bin/bash
###################################################
# 功能:
# 1. 获取config.properties和hosts.properties配置文件中的所有配置
# 2. 通用方法
###################################################
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup_config_file="$SCRIPT_DIR/../config/config.properties"
hosts_config_file="$SCRIPT_DIR/../config/hosts.properties"
fe_config_file="$SCRIPT_DIR/../config/fe.conf"
be_config_file="$SCRIPT_DIR/../config/be.conf"

# 使用普通数组存储主机名列表
declare -a host_list=()
# 使用关联数组存储配置
declare -A server_configs
# 使用关联数组存储配置
declare -A fe_configs
# 使用关联数组存储配置
declare -A be_configs
#主节点
main_node=""

# 检查文件是否存在
check_file() {
    if [[ ! -f "$1" ]]; then
        log_error "Config file not found:: $1"
        exit 1
    fi
}
# 检查文件是否存在
check_directory() {
    if [[ ! -d "$1" ]]; then
        log_error "Directory not found:: $1"
        exit 1
    fi
}
# 读取主机配置
read_hosts_config() {
    check_file "$hosts_config_file"

    local host="" port="" user="" password="" root_password="" use_sudo=""
    local first_host=true

    while IFS='=' read -r key value || [ -n "$key" ]; do
        [[ $key =~ ^[[:space:]]*# ]] && continue
        [ -z "$key" ] && continue

        key=$(echo "$key" | tr -d ' ')
        value=$(echo "$value" | tr -d ' ')

        case "$key" in
            "host")
                # 保存当前配置（如果有的话）
                if [ -n "$host" ]; then
                    server_configs["${host}_port"]=$port
                    server_configs["${host}_user"]=$user
                    server_configs["${host}_password"]=$password
                    server_configs["${host}_root_password"]=$root_password
                    server_configs["${host}_use_sudo"]=$use_sudo
                fi

                if [ "$first_host" = true ]; then
                    main_node=$value
                    first_host=false
                    log_info "Main node is set to $main_node"
                fi

                # 记录新的主机
                host=$value
                host_list+=("$value")
                port="22"  # 默认端口
                user=""
                password=""
                root_password=""
                use_sudo=""
                ;;
            "port") port=$value ;;
            "user") user=$value ;;
            "password") password=$value ;;
            "root_password") root_password=$value ;;
            "use_sudo") use_sudo=$value ;;
        esac
    done < "$hosts_config_file"

    # 保存最后一个服务器的配置
    if [ -n "$host" ]; then
        server_configs["${host}_port"]=$port
        server_configs["${host}_user"]=$user
        server_configs["${host}_password"]=$password
        server_configs["${host}_root_password"]=$root_password
        server_configs["${host}_use_sudo"]=$use_sudo
    fi
}

# 读取安装配置
read_config() {
    check_file "$setup_config_file"

    # 读取所有配置
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # 跳过注释和空行
        [[ $key =~ ^#.*$ ]] || [ -z "$key" ] && continue
        # 去除空格
        key=$(echo "$key" | tr -d ' ')
        value=$(echo "$value" | tr -d ' ')
        eval "$key='$value'"
    done < "$setup_config_file"
}

# 读取安装配置
read_fe_config() {
    check_file "$fe_config_file"

    # 读取所有配置
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # 跳过注释和空行
        [[ $key =~ ^#.*$ ]] || [ -z "$key" ] && continue
        # 去除空格
        key=$(echo "$key" | tr -d ' ')
        value=$(echo "$value" | tr -d ' ')
        fe_configs["$key"]=$value

        if [[ ${key} =~ .*_port$ ]];then
            eval "$key='$value'"
        fi
    done < "$fe_config_file"

}

# 读取安装配置
read_be_config() {
    check_file "$be_config_file"

    # 读取所有配置
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # 跳过注释和空行
        [[ $key =~ ^#.*$ ]] || [ -z "$key" ] && continue
        # 去除空格
        key=$(echo "$key" | tr -d ' ')
        value=$(echo "$value" | tr -d ' ')
        be_configs["$key"]=$value
        if [[ ${key} =~ .*_port$ ]];then
            eval "$key='$value'"
        fi
    done < "$be_config_file"

}

# 远程执行sudo+命令
remote_exec_sudo() {
    local host=$1
    local cmd=$2
    if ! sudo -u "$install_user" ssh "$install_user"@"$host" "source /etc/profile;sudo $cmd"; then
        log_warn "[$host] command failed: sudo $cmd"
        return 1
    fi
}

# 远程执行命令，不带sudo
remote_exec() {
    local host=$1
    local cmd=$2
    if ! sudo -u "$install_user" ssh "$install_user"@"$host" "source /etc/profile;$cmd"; then
        log_warn "[$host] command failed: $cmd"
        return 1
    fi
}
# 循环执行多条sudo+命令
loop_remote_exec_sudo () {
    local host=$1
    shift
    local commands=("$@")
    for command in "${commands[@]}"; do
        remote_exec_sudo "$host" "$command"
    done
}
#循环执行多个命令,不带sudo
loop_remote_exec () {
    local host=$1
    shift
    local commands=("$@")
    for command in "${commands[@]}"; do
        remote_exec "$host" "$command"
    done
}

# 检查文件是否已存在
check_directory_exists() {
    local host=$1
    local dir=$2
    remote_exec_sudo "$host" "[ -d $dir ]" && return 0 || return 1
}

# 检查文件是否已存在
check_file_exists() {
    local host=$1
    local file=$2
    remote_exec_sudo "$host" "[ -f $file ]" && return 0 || return 1
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
# 启动服务
start_service() {
    local host=$1
    local service=$2
    log_info "Starting ${service^^} on $host"
    remote_exec_sudo "$host" "systemctl start starrocks_${service}"
    log_info "$service on $host started"
}

# 停止服务
stop_service() {
    local host=$1
    local service=$2
    local service_name="starrocks_$service"
    log_info "Stopping ${service^^} on $host"

    if [ "$service" == "fe" ];then
        if remote_exec "$host" "ps -ef|grep -v grep |grep -q 'com.starrocks.StarRocksFE'"; then
            if check_file_exists "$host" "/etc/systemd/system/${service_name}.service"; then
                remote_exec_sudo "$host" "systemctl stop $service_name"
            else
                remote_exec "$host" "pkill -f 'com.starrocks.StarRocksFE'" || true
            fi
        fi
    else
        if remote_exec "$host" "ps -ef|grep -v grep |grep -q 'starrocks_be'"; then
            if check_file_exists "$host" "/etc/systemd/system/${service_name}.service"; then
                remote_exec_sudo "$host" "systemctl stop $service_name"
            else
                remote_exec "$host" "pkill -f 'starrocks_be'" || true
            fi
        fi
    fi
}

# 检查节点状态
check_service_status() {
    local host=$1
    local node_type=$2
    local count=10
    log_info "Checking $node_type status on $host"

    if [ "$node_type" = "fe" ]; then
        for _ in $(seq 0 "$count"); do
            if remote_exec_sudo "$host" "ss -tnlp | grep -q $query_port"; then
                return 0
            fi
            sleep 5
        done
        log_error "$node_type is not running on $host"
        return 1
    else
        for _ in $(seq 0 "$count"); do
            if remote_exec_sudo "$host" "ss -tnlp | grep -q $heartbeat_service_port"; then
                return 0
            fi
            sleep 5
        done
        log_error "$node_type is not running on $host"
        return 1

    fi
}



# 分发FE配置
configure_fe() {
    local host=$1
    log_info "Configuring FE on $host"

    # 检查配置文件是否存在
    if ! check_file_exists "$host" "${install_path%/}/fe/conf/fe.conf"; then
        log_error "FE configuration file not found on $host"
        return 1
    fi
    # 构造远程执行的 shell 命令
    remote_script="conf_file=\"$install_path/fe/conf/fe.conf\";"
    for key in "${!fe_configs[@]}"; do
        value="${fe_configs[$key]}"
        if [ -n "$value" ]; then
            log_info "Configuring FE $key = $value on $host"
            remote_script+="if grep -q \"^$key *= *\" \"\$conf_file\"; then "
            remote_script+="sed -i 's#^$key *= *.*#$key = $value#g' \"\$conf_file\"; "
            remote_script+="else echo \"$key = $value\" >> \"\$conf_file\"; fi; "
            commands+=("$remote_script")
        fi
    done
    loop_remote_exec "$host" "${commands[@]}"
}

# 分发BE配置
configure_be() {
    local host=$1
    log_info "Configuring BE on $host"
    local commands=()
    # 检查配置文件是否存在
    if ! check_file_exists "$host" "$install_path/be/conf/be.conf"; then
        log_error "BE configuration file not found on $host"
        return 1
    fi

    # 构造远程执行的 shell 命令
    remote_script="conf_file=\"$install_path/be/conf/be.conf\";"
    for key in "${!be_configs[@]}"; do
        value="${be_configs[$key]}"
        if [ -n "$value" ]; then
            log_info "Configuring BE $key = $value on $host"
            remote_script+="if grep -q \"^$key *= *\" \"\$conf_file\"; then "
            remote_script+="sed -i 's#^$key *= *.*#$key = $value#g' \"\$conf_file\"; "
            remote_script+="else echo \"$key = $value\" >> \"\$conf_file\"; fi; "
            commands+=("$remote_script")
        fi
    done
    loop_remote_exec "$host" "${commands[@]}"
}
# 下载StarRocks安装包
download_package() {
    local version=$1
    package_filename="StarRocks-${version}-centos-amd64.tar.gz"
    package_filepath="${package_path%/}/$package_filename"
    if ! check_file "$package_filepath"; then
        log_info "Downloading $package_filename to $package_filepath"
        if check_directory "$package_path";then
            sudo mkdir -P $package_path && sudo chown -R $install_user:$install_user $package_path
        fi
        wget -O $package_filename "${package_url%/}/$package_filename"
    else
        log_info "Install package already exists at $package_filepath"
    fi
}
# 执行mysql命令
mysql_command_exec(){
    local command=$1
    if [ -n "$fe_root_password" ];then
        mysql --connect_timeout=5 -uroot -h$leader -P$query_port -P$fe_root_password -e "$command"
    else
        mysql --connect_timeout=5 -uroot -h$leader -P$query_port -e "$command"
    fi
}

# 执行mysql命令,
mysql_command_exec_silent(){
    local command=$1
    if [ -n "$fe_root_password" ];then
        mysql --connect_timeout=5 -uroot -h$leader -P$query_port -P$fe_root_password -sse "$command"
    else
        mysql --connect_timeout=5 -uroot -h$leader -P$query_port -sse "$command"
    fi
}

# 获取服务当前版本
get_current_version() {
    local host=$1
    local service=$2
    local command=""
    local index=0
    if [ "$service" = "fe" ];then
        command="show frontends;"
        index="NF"
    elif [ "$service" = "be" ];then
        index=19
        command="show backends;"
    fi
    local result=$(mysql_command_exec_silent "$command")
    if [ -n "$result" ];then
        echo "$result" | grep "$host" | awk -F'\t' "{print \$$index}"
    fi
}

# 获取当前集群所有FE节点ip
get_fe_ip(){
    local result=$(mysql_command_exec_silent "show frontends;")
    if [ -n "$result" ];then
        while read line; do
            arr=($line)
            ip=${arr[1]}
            role=${arr[6]}
            if [ "$role" = "LEADER" ]; then
              leader_ip=$ip
            else
              fe_ip+=($ip)
            fi
        done <<< "$result"
        #将leader节点放到最后处理
        fe_ip+=("$leader_ip")
    fi
}

# 创建新的元数据快照文件并等待元数据快照文件同步至其他 FE 节点
create_image_file(){
    log_info "Creating image file on $leader_ip"
    local command=""
    local key="sys_log_dir"
    mysql_command_exec "ALTER SYSTEM CREATE IMAGE"
    start_time=$(date +"%Y-%m-%d %H:%M:%S")
    local count=36
    local index=0
    while [[ $index < $count ]]; do
        log_info "Waiting for image file creation on $leader_ip"
        # 检查leader节点的fe.log
        if [ "${fe_configs[$key]+isset}" ];then
            sys_log_dir="${fe_configs[$key]}"
            fe_log_path="${sys_log_dir%/}/fe.log"
        else
            fe_log_path="${install_path%/}/fe/log/fe.INFO"
        fi
        command="awk '\$1\" \"\$2 >= \"$start_time\"' $fe_log_path | grep -q 'push image.*to other nodes'"
        if remote_exec "$leader_ip" "$command"; then
            log_info "Create image successfully"
            break
        else
            sleep 5
            index=$((index+1))
        fi
    done
}
# 检查升级版本
check_upgrade_version() {
    local current_version=$1
    local target_version=$2
    # 如果不是升级，直接返回错误
    if [[ "$current_version" == "$upgrade_version" ]];then
        log_info "Skip upgrade $host ${service^^}, current version $current_version is equal to upgrade version $upgrade_version"
        return 1
    fi
    if echo -e "$current_version\n$target_version" | sort -V | head -n1 | grep -q "^${upgrade_version}$"; then
        log_info "Skip upgrade $host ${service^^}, current version $current_version is greater than upgrade version $upgrade_version"
        return 1
    fi

    # 提取版本号的各个部分
    local curr_major=$(echo "$current_version" | cut -d. -f1)
    local curr_minor=$(echo "$current_version" | cut -d. -f2)
    local curr_patch=$(echo "$current_version" | cut -d. -f3)
    local target_major=$(echo "$target_version" | cut -d. -f1)
    local target_minor=$(echo "$target_version" | cut -d. -f2)
    local target_patch=$(echo "$target_version" | cut -d. -f3)

    # 重大版本升级规则检查
    # v1.19 必须升级到 v2.0
    if [ "$curr_major" = "1" ] && [ "$curr_minor" = "19" ] && \
       ([ "$target_major" != "2" ] || [ "$target_minor" != "0" ]); then
        log_error "Version 1.19 must be upgraded to version 2.0"
        return 1
    fi

    # v2.5 必须升级到 v3.0
    if [ "$curr_major" = "2" ] && [ "$curr_minor" = "5" ] && \
       ([ "$target_major" != "3" ] || [ "$target_minor" != "0" ]); then
        log_error "Version 2.5 must be upgraded to version 3.0"
        return 1
    fi

    # 检查是否是跨大版本升级（major或minor版本不同）
    if [ "$curr_major" != "$target_major" ] || [ "$curr_minor" != "$target_minor" ]; then
        # 如果是从 2.0 以上版本升级，允许跨版本但给出警告
        if [ "$curr_major" -ge "2" ]; then
            local version_diff=$((target_major * 100 + target_minor - (curr_major * 100 + curr_minor)))
            if [ "$version_diff" -gt "1" ]; then
                log_info "WARNING: Upgrading across multiple major/minor versions from $current_version to $target_version"
                log_info "Recommended upgrade path: upgrade through intermediate versions"
            fi
        else
            # 2.0 之前的版本不允许跨版本升级
            log_error "Cannot upgrade across major versions before v2.0"
            return 1
        fi
    fi

    log_info "Upgrade version from $current_version to $target_version is valid"
    return 0
}
# 检查降级版本
check_downgrade_version() {
    local current_version=$1
    local target_version=$2
    # 如果不是降级，直接返回错误
    if [[ "$current_version" == "$target_version" ]];then
        log_info "Skip downgrade $host ${service^^}, current version $current_version is equal to downgrade version $target_version"
        return 1
    fi
    if echo -e "$current_version\n$target_version" | sort -V | head -n1 | grep -q "^$current_version$"; then
        log_info "Skip downgrade $host ${service^^}, current version $current_version is smaller than downgrade version $target_version"
        return 1
    fi

    # 提取版本号的各个部分
    local curr_major=$(echo "$current_version" | cut -d. -f1)
    local curr_minor=$(echo "$current_version" | cut -d. -f2)
    local curr_patch=$(echo "$current_version" | cut -d. -f3)
    local target_major=$(echo "$target_version" | cut -d. -f1)
    local target_minor=$(echo "$target_version" | cut -d. -f2)
    local target_patch=$(echo "$target_version" | cut -d. -f3)

    # 特殊规则：v3.3 不能降级到 v3.2.0-2
    if [ "$curr_major" = "3" ] && [ "$curr_minor" = "3" ] && \
       [ "$target_major" = "3" ] && [ "$target_minor" = "2" ] && \
       [ "$target_patch" -lt "3" ]; then
        log_error "Cannot downgrade from v3.3 to v3.2.0-2 directly due to metadata loss risk. Please use v3.2.3 or higher."
        return 1
    fi

    # 特殊规则：v3.0 只能降级到 v2.5.3+
    if [ "$curr_major" = "3" ] && [ "$curr_minor" = "0" ] && \
       [ "$target_major" = "2" ] && \
       ([ "$target_minor" -lt "5" ] || \
       ([ "$target_minor" = "5" ] && [ "$target_patch" -lt "3" ])); then
        log_error "Version 3.0 can only be downgraded to v2.5.3 or higher versions"
        return 1
    fi

    # 特殊规则：不能直接降级到 v1.19
    if [ "$target_major" = "1" ] && [ "$target_minor" = "19" ]; then
        log_error "Cannot downgrade directly to v1.19. Must downgrade to v2.0 first"
        return 1
    fi

    # 检查是否是跨大版本降级（major或minor版本不同）
    if [ "$curr_major" != "$target_major" ] || [ "$curr_minor" != "$target_minor" ]; then
        # 检查是否跨多个大版本
        local version_diff=$((curr_major * 100 + curr_minor - (target_major * 100 + target_minor)))
        if [ "$version_diff" -gt "1" ]; then
            log_error "Cannot downgrade across multiple major/minor versions directly from $current_version to $target_version"
            log_error "Please downgrade step by step through intermediate versions"
            return 1
        fi
    fi

    # 如果只是小版本降级，允许直接降级
    log_info "Downgrade version from $current_version to $target_version is valid"
    return 0
}