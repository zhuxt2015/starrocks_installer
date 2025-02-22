#!/bin/bash
###################################################
# 功能:
# 1. 检查服务器支持AVX2
# 2. 检查节点内存和cpu
# 3. 检查端口占用
###################################################
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"
source "$SCRIPT_DIR/common.sh"

# 检查单个节点的AVX2支持
check_avx2() {
    local host=$1
    log_info "Checking AVX2 support on $host"
    if remote_exec_sudo "$host" "grep -q avx2 /proc/cpuinfo"; then
        log_info "[$host] CPU supports AVX2"
        return 0
    else
        log_error "[$host] CPU does not support AVX2"
        return 1
    fi
}

# 检查节点规格
check_node_specs() {
    local host=$1
    local is_fe=$2

    log_info "Checking hardware specifications on $host"

    # 获取CPU核心数和内存大小
    local cpu_cores=$(remote_exec_sudo "$host" "nproc")
    local total_mem=$(remote_exec_sudo "$host" "free -g | awk '/^Mem:/{print \$2}'")

    if [ "$is_fe" = true ]; then
        # FE节点检查
        if [[ $cpu_cores -lt 8 ]]; then
            log_warn "[$host] FE node CPU cores less than required: current $cpu_cores, required 8"
        else
            log_info "[$host] FE node CPU cores check passed"
        fi

        if [[ $total_mem -lt 16 ]]; then
            log_warn "[$host] FE node memory less than required: current ${total_mem}GB, required 16GB"
        else
            log_info "[$host] FE node memory check passed"
        fi
    else
        # BE节点检查
        if [[ $cpu_cores -lt 16 ]]; then
            log_warn "[$host] BE node CPU cores less than required: current $cpu_cores, required 16"
        else
            log_info "[$host] BE node CPU cores check passed"
        fi

        if [[ $total_mem -lt 64 ]]; then
            log_warn "[$host] BE node memory less than required: current ${total_mem}GB, required 64GB"
        else
            log_info "[$host] BE node memory check passed"
        fi
    fi
}

# 检查端口占用
check_ports() {
    local host=$1
    local is_fe=$2

    log_info "Checking port usage on $host"

    if [ "$is_fe" = true ]; then
        # FE节点端口检查
        for key in "${!fe_configs[@]}"; do
            port="${fe_configs[$key]}"
            if [[ -n "$port" ]] && [[ ${key,,} =~ .*_port$ ]]; then
                if remote_exec_sudo "$host" "ss -tlnp | grep -q ':$port '"; then
                    log_warn "[$host] FE port $port is already in use"
                else
                    log_info "[$host] FE port $port is available"
                fi
            fi
        done
    else
        # BE节点端口检查
        for key in "${!be_configs[@]}"; do
            port="${be_configs[$key]}"
            if [[ -n "$port" ]] && [[ ${key,,} =~ .*_port$ ]]; then
                if remote_exec_sudo "$host" "ss -tlnp | grep -q ':$port '"; then
                    log_warn "[$host] BE port $port is already in use"
                else
                    log_info "[$host] BE port $port is available"
                fi
            fi
        done
    fi
}

# 检查单个节点
check_node() {
    local host=$1
    local is_fe=$2

    log_info "Starting checks for host: $host"

    # 检查AVX2支持
    check_avx2 "$host"

    # 检查节点规格
    check_node_specs "$host" "$is_fe"

    # 检查端口占用
    check_ports "$host" "$is_fe"
}

# 主函数
main() {
    log_info "Starting environment check..."

    # 读取配置文件
    read_config
    read_fe_config
    read_be_config

    # 检查主FE节点
    log_info "Checking leader FE node..."
    check_node "$leader" true

    # 检查从FE节点
    if [ ! -z "$follower" ]; then
        IFS=',' read -ra FOLLOWERS <<< "$follower"
        for follower_host in "${FOLLOWERS[@]}"; do
            log_info "Checking follower FE node: $follower_host"
            check_node "$follower_host" true
        done
    fi

    # 检查BE节点
    if [ ! -z "$backend" ]; then
        IFS=',' read -ra BACKENDS <<< "$backend"
        for backend_host in "${BACKENDS[@]}"; do
            log_info "Checking BE node: $backend_host"
            check_node "$backend_host" false
        done
    fi

    log_info "Environment check completed"
}

# 执行主函数
main