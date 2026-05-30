#!/bin/bash
###################################################
# 功能:
# 1. 统一管理 FE/BE/集群的启动与停止
###################################################
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/log.sh"
source "$SCRIPT_DIR/scripts/common.sh"

usage() {
    cat <<'EOF'
Usage:
  bash ./cluster.sh start [all|fe|be]
  bash ./cluster.sh stop [all|fe|be]
EOF
}

collect_frontend_hosts() {
    local frontend_hosts=()
    if [ -n "${leader:-}" ]; then
        frontend_hosts+=("$leader")
    fi
    if [ -n "${follower:-}" ]; then
        IFS=',' read -ra FOLLOWERS <<< "$follower"
        frontend_hosts+=("${FOLLOWERS[@]}")
    fi
    printf '%s\n' "${frontend_hosts[@]}"
}

run_fe_action() {
    local action=$1
    local frontend_host=""

    read_config
    read_fe_config
    while IFS= read -r frontend_host; do
        [ -z "$frontend_host" ] && continue
        "${action}_service" "$frontend_host" "fe"
        if [ "$action" = "start" ]; then
            check_service_status "$frontend_host" "fe"
        fi
    done < <(collect_frontend_hosts)
}

run_be_action() {
    local action=$1
    local backend_host=""

    read_config
    read_be_config
    if [ -z "${backend:-}" ]; then
        return 0
    fi
    IFS=',' read -ra BACKENDS <<< "$backend"
    for backend_host in "${BACKENDS[@]}"; do
        "${action}_service" "$backend_host" "be"
        if [ "$action" = "start" ]; then
            check_service_status "$backend_host" "be"
        fi
    done
}

main() {
    local action=${1:-}
    local target=${2:-all}

    if [[ "$action" != "start" && "$action" != "stop" ]]; then
        usage
        exit 1
    fi

    case "$target" in
        all)
            run_fe_action "$action"
            run_be_action "$action"
            ;;
        fe)
            run_fe_action "$action"
            ;;
        be)
            run_be_action "$action"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
