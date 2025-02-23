#!/bin/bash
###################################################
# 功能:
# 1. 降级所有服务
###################################################
set -eu
START_TIME=$(date +%s)

DOWNGRADE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source $DOWNGRADE_DIR/../scripts/log.sh
source $DOWNGRADE_DIR/../scripts/common.sh
read_config
read_fe_config
get_fe_ip
create_image_file
bash $DOWNGRADE_DIR/downgrade_fe.sh
bash $DOWNGRADE_DIR/downgrade_be.sh
# 计算升级时长
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))
log_info "Total downgrade time: ${MINUTES}m${SECONDS}s"