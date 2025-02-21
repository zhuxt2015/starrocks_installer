#!/bin/bash
###################################################
# 功能:停止所有FE服务
###################################################
set -eu
source "scripts/log.sh"
source "scripts/common.sh"

main() {
    read_config
    read_fe_config
    # 停止FE服务
    if [ -n "$leader" ]; then
        local frontend_hosts=()
        frontend_hosts+=("$leader")
        if [ -n "$follower" ];then
            IFS=',' read -ra FOLLOWERS <<< "$follower"
            frontend_hosts+=("${FOLLOWERS[@]}")
        fi
        for frontend_host in "${frontend_hosts[@]}"; do
            stop_service "$frontend_host" "fe"
       done
    fi
}
main