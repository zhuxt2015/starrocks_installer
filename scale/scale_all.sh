#!/bin/bash

set -eu
START_TIME=$(date +%s)

SCALE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source $SCALE_DIR/../scripts/log.sh

# 执行FE扩容
log_info "开始扩容FE节点..."
if ! bash $SCALE_DIR/scale_fe.sh; then
    log_error "FE扩容失败，终止扩容流程"
    exit 1
fi

# 执行BE扩容
log_info "开始扩容BE节点..."
if ! bash $SCALE_DIR/scale_be.sh; then
    log_error "BE扩容失败"
    exit 1
fi

log_info "所有节点扩容完成" 
# 计算时长
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))
log_info "Total scale time: ${MINUTES}m${SECONDS}s"
print_cluster_info