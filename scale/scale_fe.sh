#!/bin/bash
###################################################
# 功能: 扩容FE节点
###################################################

function main() {
    # 加载公共函数
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../scripts/log.sh"
    source "$SCRIPT_DIR/../scripts/common.sh"

    read_config
    read_hosts_config
    read_fe_config

    # 检查参数
     if [[ -z "${scale_fe_ips}" ]]; then
        log_error "未配置FE扩容节点IP列表,配置项是config/config.properties中的scale_fe_ips"
        return 1
    fi
    
    log_info "开始FE扩容..."
    download_package "$starrocks_version"
    IFS=',' read -ra FE_IPS <<< "$scale_fe_ips"
    for frontend_host in "${FE_IPS[@]}"; do
        log_info "Installing FE on $frontend_host"
        #检查ip是否已经存在
        if ! check_ip_in_cluster "$frontend_host" "fe"; then
            exit 1
        fi
        #免密
        port="${server_configs[${frontend_host}_port]}"
        user="${server_configs[${frontend_host}_user]}"
        password="${server_configs[${frontend_host}_password]}"
        root_password="${server_configs[${frontend_host}_root_password]}"
        use_sudo="${server_configs[${frontend_host}_use_sudo]}"
        
        log_info "Using configuration:"
        echo "Port: $port"
        echo "User: $user"
        echo "Use Sudo: $use_sudo"
        
        setup_server "$frontend_host" "$port" "$user" "$password" "$root_password" "$use_sudo" "$install_user" "$main_node"
        #初始化环境
        remote_init "$frontend_host"
        check_init_status "$frontend_host"
        #停止服务
        stop_service "$frontend_host" "fe"
        #分发安装包
        distribute_install_file "$frontend_host"
        #创建目录
        create_directories "$frontend_host" "fe"
        #解压安装包
        decompress_package "$frontend_host" "fe"
        #加入集群
        add_to_cluster "$frontend_host" "fe"
        #分发配置
        configure_fe "$frontend_host"
        #follower第一次启动
        follower_first_start "$frontend_host"
        create_service "$frontend_host" "fe"
        check_service_status "$frontend_host" "fe"
        log_info "Install FE on $frontend_host complete"
    done
    
    log_info "FE扩容完成"
    print_cluster_info
    return 0
}

# 执行FE扩容
main