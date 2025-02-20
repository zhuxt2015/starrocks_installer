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
    # 处理版本号变量
    install_package=$(echo "$install_package" | sed "s#\${starrocks_version}#$starrocks_version#g")
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

# 远程执行命令的函数
remote_exec() {
    local host=$1
    local cmd=$2
    if ! sudo -u "$install_user" ssh "$install_user"@"$host" "source /etc/profile;sudo $cmd"; then
        log_warn "[$host] command failed: sudo $cmd"
        return 1
    fi
}
# 检查文件是否已存在
check_directory_exists() {
    local host=$1
    local dir=$2
    remote_exec "$host" "[ -d $dir ]" && return 0 || return 1
}

# 检查文件是否已存在
check_file_exists() {
    local host=$1
    local file=$2
    remote_exec "$host" "[ -f $file ]" && return 0 || return 1
}

# 循环执行多条命令
loop_remote_exec () {
    local host=$1
    shift
    local commands=("$@")
    for command in "${commands[@]}"; do
        remote_exec "$host" "$command"
    done
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

# 停止服务
stop_service() {
    local host=$1
    local service=$2
    local service_name="starrocks_$service"
    log_info "Stopping $service on $host"

    if [ "$service" == "fe" ];then
        if remote_exec "$host" "ps -ef|grep -v grep |grep -q 'com.starrocks.StarRocksFE'"; then
            if check_file_exists "$host" "/etc/systemd/system/${service_name}.service"; then
                remote_exec "$host" "systemctl stop $service_name"
            else
                remote_exec "$host" "pkill -9 -f 'com.starrocks.StarRocksFE'" || true
            fi
        fi
    else
        if remote_exec "$host" "ps -ef|grep -v grep |grep -q 'starrocks_be'"; then
            if check_file_exists "$host" "/etc/systemd/system/${service_name}.service"; then
                remote_exec "$host" "systemctl stop $service_name"
            else
                remote_exec "$host" "pkill -9 -f 'starrocks_be'" || true
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
            if remote_exec "$host" "ss -tnlp | grep -q $query_port"; then
                return 0
            fi
            sleep 5
        done
        log_error "$node_type is not running on $host"
        return 1
    else
        for _ in $(seq 0 "$count"); do
            if remote_exec "$host" "ss -tnlp | grep -q $be_port"; then
                return 0
            fi
            sleep 5
        done
        log_error "$node_type is not running on $host"
        return 1

    fi
}

#循环执行多个命令
loop_nosudo_remote_exec () {
    local host=$1
    shift
    local commands=("$@")
    for command in "${commands[@]}"; do
        sudo -u "$install_user" ssh "$install_user"@"$host" "source /etc/profile;$command"
    done
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
            remote_script+="if grep -q \"^$key *= *\" \"\$conf_file\"; then "
            remote_script+="sed -i 's#^$key *= *.*#$key = $value#g' \"\$conf_file\"; "
            remote_script+="else echo \"$key = $value\" >> \"\$conf_file\"; fi; "
            commands+=("$remote_script")
        fi
    done
    loop_nosudo_remote_exec "$host" "${commands[@]}"
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
            remote_script+="if grep -q \"^$key *= *\" \"\$conf_file\"; then "
            remote_script+="sed -i 's#^$key *= *.*#$key = $value#g' \"\$conf_file\"; "
            remote_script+="else echo \"$key = $value\" >> \"\$conf_file\"; fi; "
            commands+=("$remote_script")
        fi
    done
    loop_nosudo_remote_exec "$host" "${commands[@]}"
}