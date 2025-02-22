#!/bin/bash
###################################################
# 功能:
# 1. 升级所有服务
###################################################
set -eu
START_TIME=$(date +%s)

UPGRADE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash $UPGRADE_DIR/upgrade_be.sh
bash $UPGRADE_DIR/upgrade_fe.sh
# 计算升级时长
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))
log_info "Total Upgrade time: ${MINUTES}m${SECONDS}s"