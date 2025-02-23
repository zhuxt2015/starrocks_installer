#!/bin/bash
###################################################
# 功能:
# 1. 升级所有服务
###################################################
set -eu
START_TIME=$(date +%s)

UPGRADE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source $UPGRADE_DIR/../scripts/log.sh
source $UPGRADE_DIR/../scripts/common.sh
read_config
read_fe_config
get_fe_ip
create_image_file
bash $UPGRADE_DIR/upgrade_be.sh
bash $UPGRADE_DIR/upgrade_fe.sh
# 计算升级时长
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))
log_info "Total upgrade time: ${MINUTES}m${SECONDS}s"