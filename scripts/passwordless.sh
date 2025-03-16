#!/bin/bash
###################################################
# 功能:
# 1. 如果install_user不存在，则创建用户
# 2. 主节install_user点对其他节点免密
# 3. install_user拥有sudo权限
###################################################
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"
source "$SCRIPT_DIR/common.sh"

# 检查是否安装 sshpass
check_sshpass() {
    if ! command -v sshpass &> /dev/null; then
        log_error "sshpass is not installed. Please install it before running the script."
        exit 1
    fi
}

# 主函数
main() {

    read_config
    read_hosts_config
    check_sshpass

    # 处理所有服务器
    for host in "${host_list[@]}"; do
        log_info "Processing server: $host"
        
        # 获取该服务器的配置
        port="${server_configs[${host}_port]}"
        user="${server_configs[${host}_user]}"
        password="${server_configs[${host}_password]}"
        root_password="${server_configs[${host}_root_password]}"
        use_sudo="${server_configs[${host}_use_sudo]}"
        
        log_info "Using configuration:"
        echo "Port: $port"
        echo "User: $user"
        echo "Use Sudo: $use_sudo"
        
        setup_server "$host" "$port" "$user" "$password" "$root_password" "$use_sudo" "$install_user" "$main_node"
    done
}

main "$@"