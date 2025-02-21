#!/bin/bash
###################################################
# 功能:启动所有FE服务
###################################################
set -eu

source "scripts/log.sh"
source "scripts/common.sh"

main() {
    read_config
    read_fe_config
    # 启动FE服务
    if [ -n "$leader" ]; then
        local frontend_hosts=()
        frontend_hosts+=("$leader")
        if [ -n "$follower" ];then
            IFS=',' read -ra FOLLOWERS <<< "$follower"
            frontend_hosts+=("${FOLLOWERS[@]}")
        fi
        for frontend_host in "${frontend_hosts[@]}"; do
            start_service "$frontend_host" "fe"
            check_service_status "$frontend_host" "fe"
       done
    fi
}
main