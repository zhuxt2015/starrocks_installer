#!/bin/bash
###################################################
# 功能:停止所有服务
###################################################
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/log.sh"
source "$SCRIPT_DIR/scripts/common.sh"

stop_service() {
    local host=$1
    local service=$2
    log_info "Stopping $service on $host"
    remote_exec "$host" "systemctl stop starrocks_${service}"
    log_info "$service on $host stopped"
}

main() {
    read_hosts_config
    read_config
    read_fe_config
    read_be_config
    # 停止FE服务
    if [ -n "$leader" ]; then
        local frontend_hosts=()
        frontend_hosts+=("$leader")
        if [ -n "$follower" ];then
            IFS=',' read -ra FOLLOWERS <<< "$follower"
            frontend_hosts+=("${FOLLOWERS[@]}")
        fi
        for frontend_host in "${FRONTENDS[@]}"; do
            stop_service "$frontend_host" "fe"
       done
    fi
    # 停止BE服务
    if [ -n "$backend" ]; then
        IFS=',' read -ra BACKENDS <<< "$backend"
        for backend_host in "${BACKENDS[@]}"; do
            stop_service "$backend_host" "be"
        done
    fi
}
main