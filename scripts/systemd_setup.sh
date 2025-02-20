#!/bin/bash
###################################################
# 功能: StarRocks FE/BE服务加入系统服务中，实现开机自启动和进程宕机自恢复
###################################################
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"
source "$SCRIPT_DIR/common.sh"

# 加载配置文件
read_config

create_service() {
    local host=$1
    local service=$2
    local service_name="starrocks_${service}"
    local work_dir="${install_path%/}/${service}"
    local start_script="$work_dir/bin/start_${service}.sh"
    local stop_script="$work_dir/bin/stop_${service}.sh"
    local service_file="/etc/systemd/system/${service_name}.service"

    log_info "Creating systemd service file: $service_file"
    cat <<EOF | remote_exec $host "tee $service_file >/dev/null"
[Unit]
Description=StarRocks ${service_name^} Service
After=network.target

[Service]
Environment=JAVA_HOME=$java_home
User=$install_user
Group=$install_user
WorkingDirectory=$work_dir
ExecStart=$start_script
ExecStop=$stop_script
LimitNOFILE=655350
LimitNPROC=655350
StartLimitInterval=180
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

    log_info "$host Reloading systemd daemon..."
    remote_exec "$host" "systemctl daemon-reload"

    log_info "$host Enabling and starting $service_name service..."
    remote_exec "$host" "systemctl enable $service_name"
    remote_exec "$host" "systemctl start $service_name"
    log_info "$host $service_name service setup complete."
}

# 安装 FE 节点
if [ -n "$leader" ]; then
    stop_service "$leader" "fe"
    create_service "$leader" "fe"
    check_service_status "$leader" "fe"
fi
if [ -n "$follower" ]; then
    IFS=',' read -ra FOLLOWERS <<< "$follower"
    for follower_host in "${FOLLOWERS[@]}"; do
        stop_service "$follower_host" "fe"
        create_service "$follower_host" "fe"
        check_service_status "$follower_host" "fe"
    done
fi

# 安装 BE 节点
if [ -n "$backend" ]; then
    IFS=',' read -ra BACKENDS <<< "$backend"
    for backend_host in "${BACKENDS[@]}"; do
        stop_service "$backend_host" "be"
        create_service "$backend_host" "be"
        check_service_status "$backend_host" "be"
    done
fi

echo "All services systemd configured successfully."
