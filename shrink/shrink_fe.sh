#!/bin/bash

set -eu

# 检查BE节点状态
function check_fe_status() {
    local ip=$1
    local status
    status=$(mysql_command_exec "show frontends;" | grep "$ip")
    if [ -z "$status" ]; then
        return 0
    fi
    return 1
}

function main() {
    # 加载公共函数
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../scripts/log.sh"
    source "$SCRIPT_DIR/../scripts/common.sh"

    read_config
    read_fe_config
    
    if [[ -z "${shrink_fe_ips}" ]]; then
        log_warn "未配置FE缩容节点,配置项是config/config.properties中的shrink_fe_ips"
        return 0
    fi
    
    log_info "开始FE缩容..."
    
    IFS=',' read -ra FE_IPS <<< "$shrink_fe_ips"
    for ip in "${FE_IPS[@]}"; do
        # 从集群移除FE节点
        log_info "从集群移除FE节点 $ip"
        mysql_command_exec "ALTER SYSTEM DROP FOLLOWER '$ip:$edit_log_port';"
            
        # 等待节点状态更新
        log_info "等待FE节点状态更新..."
        for ((i=0; i<10; i++)); do
            if check_fe_status "$ip"; then
                break
            fi
            sleep 3
        done
            
        # 停止FE进程
        stop_service "$ip" "fe"
        
        log_info "FE节点 $ip 缩容成功"
    done
    
    log_info "FE缩容完成"
    print_cluster_info
    return 0
}

# 执行FE缩容
main