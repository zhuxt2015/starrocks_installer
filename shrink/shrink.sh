#!/bin/bash
###################################################
# 功能:
# 1. 统一管理 FE/BE/集群缩容
###################################################
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/log.sh"

usage() {
    cat <<'EOF'
Usage:
  bash ./shrink/shrink.sh [all|fe|be]
EOF
}

main() {
    local target=${1:-all}
    local start_time
    local end_time
    local duration

    start_time=$(date +%s)

    case "$target" in
        all)
            log_info "开始缩容BE节点..."
            bash "$SCRIPT_DIR/shrink_be.sh"
            log_info "开始缩容FE节点..."
            bash "$SCRIPT_DIR/shrink_fe.sh"
            ;;
        fe)
            log_info "开始缩容FE节点..."
            bash "$SCRIPT_DIR/shrink_fe.sh"
            ;;
        be)
            log_info "开始缩容BE节点..."
            bash "$SCRIPT_DIR/shrink_be.sh"
            ;;
        *)
            usage
            exit 1
            ;;
    esac

    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log_info "Total shrink time: $((duration / 60))m$((duration % 60))s"
}

main "$@"
