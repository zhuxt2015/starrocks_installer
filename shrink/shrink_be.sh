#!/bin/bash

set -eu

TabletNum=0

# 检查BE节点状态
function check_be_status() {
    local ip=$1
    local status
    backend=$(mysql_command_exec_silent "show backends;")
    status=$(echo "$backend"|grep "$ip")
    if [ -z "$status" ]; then
        return 0
    fi
    TabletNum=$(echo "$backend"|grep "$ip"|awk '{print $14}')
    return 1
}

function main() {
    # 加载公共函数
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../scripts/log.sh"
    source "$SCRIPT_DIR/../scripts/common.sh"

    read_config
    read_fe_config
    read_be_config

    # 检查参数
     if [[ -z "${shrink_be_ips}" ]]; then
        log_error "未配置BE缩容节点IP列表,配置项是config/config.properties中的shrink_be_ips"
        return 1
    fi
    local replication_num_command="admin show frontend config like 'default_replication_num'"
    local backends_command="show backends"
    log_info "开始BE缩容..."
    
    IFS=',' read -ra BE_IPS <<< "$shrink_be_ips"
    for ip in "${BE_IPS[@]}"; do
        # 如果过BE剩余数量少于等于默认副本数default_replication_num,则不执行缩容
        default_replication_num=$(mysql_command_exec_silent "$replication_num_command" | awk '{print $3}')
        be_num=$(mysql_command_exec_silent "$backends_command" | wc -l)
        if [ "$be_num" -le "$default_replication_num" ]; then
            log_error "BE节点数量为${be_num}少于等于默认副本数${default_replication_num},不执行缩容"
            return 1
        fi
        # 从集群退役BE节点
        log_info "从集群退役BE节点 $ip"
        mysql_command_exec "ALTER SYSTEM DECOMMISSION BACKEND '$ip:$heartbeat_service_port';"
            
        # 等待数据迁移完成
        log_info "等待数据迁移完成..."
        while ! check_be_status $ip; do
            log_info "BE节点 $ip 数据迁移中,剩余${TabletNum}个Tablet"
            sleep 30
        done
        
        # 停止BE进程
        stop_service "$ip" "be"
        
        log_info "BE节点 $ip 缩容成功"
    done
    
    log_info "BE缩容完成"
    print_cluster_info
    return 0
}

# 执行BE缩容
main