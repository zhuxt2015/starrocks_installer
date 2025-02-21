#!/bin/bash
###################################################
# 功能:
# 1. 升级所有服务
###################################################
set -eu
UPGRADE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash $UPGRADE_DIR/upgrade_be.sh
bash $UPGRADE_DIR/upgrade_fe.sh
