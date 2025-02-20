#!/bin/bash
###################################################
# 功能:
# 1. ssh免密
# 2. 环境检查
# 3. 环境初始化
# 4. 部署
###################################################
set -eu
START_TIME=$(date +%s)

bash scripts/log.sh
bash scripts/passwordless.sh
bash scripts/check_environment.sh
bash scripts/init_environment.sh
bash scripts/deploy.sh
# 计算安装时长
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))
log_info "Total installation time: ${MINUTES}m${SECONDS}s"
log_info "Start FE service: sudo systemctl start starrocks_fe"
log_info "Stop FE service: sudo systemctl stop starrocks_fe"
log_info "Check FE service status: sudo systemctl status starrocks_fe"
log_info "Restart FE service: sudo systemctl restart starrocks_fe"

log_info "Start BE service: sudo systemctl start starrocks_be"
log_info "Start BE service: sudo systemctl stop starrocks_be"
log_info "Check BE service status: sudo systemctl status starrocks_be"
log_info "Restart BE service: sudo systemctl restart starrocks_be"

log_info "Start Cluster: bash ./start_cluster.sh"
log_info "Stop Cluster: bash ./stop_cluster.sh"
log_info "uninstall Cluster: bash ./uninstall.sh"