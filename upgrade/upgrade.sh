#!/bin/bash
###################################################
# 功能:
# 1. 统一管理 FE/BE/集群升级
###################################################
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/log.sh"
source "$SCRIPT_DIR/../scripts/common.sh"

usage() {
    cat <<'EOF'
Usage:
  bash ./upgrade/upgrade.sh [all|fe|be]
EOF
}

prepare_fe_metadata_snapshot() {
    read_config
    read_fe_config
    get_fe_ip
    create_image_file
}

main() {
    local target=${1:-all}
    local start_time
    local end_time
    local duration

    start_time=$(date +%s)

    case "$target" in
        all)
            prepare_fe_metadata_snapshot
            bash "$SCRIPT_DIR/upgrade_be.sh"
            bash "$SCRIPT_DIR/upgrade_fe.sh"
            ;;
        fe)
            prepare_fe_metadata_snapshot
            bash "$SCRIPT_DIR/upgrade_fe.sh"
            ;;
        be)
            bash "$SCRIPT_DIR/upgrade_be.sh"
            ;;
        *)
            usage
            exit 1
            ;;
    esac

    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log_info "Total upgrade time: $((duration / 60))m$((duration % 60))s"
}

main "$@"
