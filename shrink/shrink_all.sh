#!/bin/bash

set -eu
START_TIME=$(date +%s)

SHRINK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source $SHRINK_DIR/../scripts/log.sh

# 执行BE缩容（先缩容BE，再缩容FE）
log_info "开始缩容BE节点..."
if ! bash $SHRINK_DIR/shrink_be.sh; then
    log_error "BE缩容失败，终止缩容流程"
    exit 1
fi

# 执行FE缩容
log_info "开始缩容FE节点..."
if ! bash $SHRINK_DIR/shrink_fe.sh; then
    log_error "FE缩容失败"
    exit 1
fi

log_info "所有节点缩容完成"

# 计算时长
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))
log_info "Total shrink time: ${MINUTES}m${SECONDS}s"