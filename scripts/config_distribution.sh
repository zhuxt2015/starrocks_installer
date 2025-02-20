#!/bin/bash
###################################################
# 功能:
# 1. 分发config/fe.conf中的配置到所有FE节点
# 2. 分发config/be.conf中的配置到所有BE节点
###################################################
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"
source "$SCRIPT_DIR/common.sh"

main() {
    #参数不等于1个直接退出脚本并提示用户用法
    if [ $# -ne 1 ]; then
        echo "Usage: $0 fe or $0 be"
        exit 1
    fi
    read_config
    
    if [ "$1" = "fe" ];then
        read_fe_config
        # 安装从节点 FE
        if [ -n "$follower" ] && [ -n "$leader" ]; then
            IFS=',' read -ra FOLLOWERS <<< "$follower"
            FRONTENDS=("$leader" "${FOLLOWERS[@]}")
            for frontend_host in "${FRONTENDS[@]}"; do
                configure_fe "$frontend_host"
            done
        fi
    elif [ "$1" = "be" ]; then
        read_be_config
        if [ -n "$backend" ]; then
            IFS=',' read -ra BACKENDS <<< "$backend"
            for backend_host in "${BACKENDS[@]}"; do
                configure_be "$backend_host"
            done
        fi
    else
        log_error "Invalid argument: $1, Usage: $0 fe or $0 be"
    fi
}
