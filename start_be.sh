#!/bin/bash
###################################################
# 功能:启动所有BE服务
###################################################
set -eu

source "scripts/log.sh"
source "scripts/common.sh"

main() {
    read_config
    read_be_config
    # 启动BE服务
    if [ -n "$backend" ]; then
        IFS=',' read -ra BACKENDS <<< "$backend"
        for backend_host in "${BACKENDS[@]}"; do
            start_service "$backend_host" "be"
            check_service_status "$backend_host" "be"
        done
    fi
}
main