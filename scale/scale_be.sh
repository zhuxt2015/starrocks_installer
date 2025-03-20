#!/bin/bash

function main() {
    # 加载公共函数
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../scripts/log.sh"
    source "$SCRIPT_DIR/../scripts/common.sh"

    read_config
    read_hosts_config
    read_fe_config
    read_be_config

    # 检查参数
     if [[ -z "${scale_be_ips}" ]]; then
        log_error "未配置BE扩容节点IP列表,配置项是config/config.properties中的scale_be_ips"
        return 1
    fi
    
    log_info "开始BE扩容..."
    download_package "$starrocks_version"
    IFS=',' read -ra BE_IPS <<< "$scale_be_ips"
    for backend_host in "${BE_IPS[@]}"; do
        log_info "Installing BE on $backend_host"
        #检查ip是否已经存在
        if ! check_ip_in_cluster "$backend_host" "fe"; then
            exit 1
        fi
        #免密
        port="${server_configs[${backend_host}_port]}"
        user="${server_configs[${backend_host}_user]}"
        password="${server_configs[${backend_host}_password]}"
        root_password="${server_configs[${backend_host}_root_password]}"
        use_sudo="${server_configs[${backend_host}_use_sudo]}"
        
        log_info "Using configuration:"
        echo "Port: $port"
        echo "User: $user"
        echo "Use Sudo: $use_sudo"
        
        setup_server "$backend_host" "$port" "$user" "$password" "$root_password" "$use_sudo" "$install_user" "$main_node"
        #初始化环境
        remote_init "$backend_host"
        check_init_status "$backend_host"
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
    
    log_info "BE扩容完成"
    print_cluster_info
    return 0
}

# 执行BE扩容
main 