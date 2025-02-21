#!/bin/bash
###################################################
# 功能:停止所有BE服务
###################################################
set -eu
source "scripts/log.sh"
source "scripts/common.sh"

main() {
    read_config
    read_be_config
    # 停止BE服务
    if [ -n "$backend" ]; then
        IFS=',' read -ra BACKENDS <<< "$backend"
        for backend_host in "${BACKENDS[@]}"; do
            stop_service "$backend_host" "be"
        done
    fi
}
main