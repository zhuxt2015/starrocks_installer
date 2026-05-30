#!/bin/bash
###################################################
# 功能: 安装StarRocks AuditLoader审计日志插件
# 1. 在FE leader节点启动Python HTTP文件服务
# 2. 创建审计日志数据库和表
# 3. 通过HTTP安装AuditLoader插件
###################################################
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/log.sh"
source "$SCRIPT_DIR/common.sh"

mysql_exec() {
    local sql=$1
    if [ -n "${fe_root_password:-}" ]; then
        mysql --connect_timeout=5 -uroot -h"$leader" -P"$query_port" -p"$fe_root_password" -e "$sql"
    else
        mysql --connect_timeout=5 -uroot -h"$leader" -P"$query_port" -e "$sql"
    fi
}

mysql_exec_file() {
    local sql_file=$1
    if [ -n "${fe_root_password:-}" ]; then
        mysql --connect_timeout=5 -uroot -h"$leader" -P"$query_port" -p"$fe_root_password" < "$sql_file"
    else
        mysql --connect_timeout=5 -uroot -h"$leader" -P"$query_port" < "$sql_file"
    fi
}

mysql_exec_silent() {
    local sql=$1
    if [ -n "${fe_root_password:-}" ]; then
        mysql --connect_timeout=5 -uroot -h"$leader" -P"$query_port" -p"$fe_root_password" -sse "$sql"
    else
        mysql --connect_timeout=5 -uroot -h"$leader" -P"$query_port" -sse "$sql"
    fi
}

resolve_auditloader_package() {
    local package=${auditloader_package:-./auditloader.zip}
    if [[ "$package" != /* ]]; then
        package="$PROJECT_DIR/$package"
    fi
    check_file "$package"
    printf '%s' "$package"
}

build_auditloader_package() {
    local source_package=$1
    local output_package=$2
    local work_dir
    work_dir=$(mktemp -d /tmp/auditloader.XXXXXX)
    trap 'rm -rf "$work_dir"' RETURN

    unzip -q "$source_package" -d "$work_dir"
    sed -i.bak \
        -e "s#^frontend_host_port=.*#frontend_host_port=127.0.0.1:${http_port}#" \
        -e "s#^database=.*#database=starrocks_audit_db__#" \
        -e "s#^table=.*#table=starrocks_audit_tbl__#" \
        -e "s#^user=.*#user=${auditloader_user}#" \
        -e "s#^password=.*#password=${auditloader_password}#" \
        "$work_dir/plugin.conf"
    rm -f "$work_dir/plugin.conf.bak"
    rm -f "$output_package"

    (
        cd "$work_dir"
        zip -q -r "$output_package" auditloader.jar plugin.conf plugin.properties
    )
}

start_auditloader_http_service() {
    local package=$1
    local remote_dir="${install_path%/}/auditloader_http"
    local remote_package="$remote_dir/auditloader.zip"
    local service_name="auditloader-http"
    local python_bin

    log_info "Uploading AuditLoader package to $leader:$remote_package"
    remote_exec_sudo "$leader" "mkdir -p $remote_dir && chown -R $install_user:$install_user $remote_dir"
    sudo -u "$install_user" scp "$package" "$install_user@$leader:$remote_package"

    python_bin=$(remote_exec_sudo "$leader" "command -v python3 || command -v python" | tail -n 1)
    if [ -z "$python_bin" ]; then
        log_error "python3/python not found on FE leader $leader"
        exit 1
    fi

    log_info "Starting AuditLoader HTTP service on $leader:${auditloader_http_port}"
    remote_exec_sudo "$leader" "cat > /etc/systemd/system/${service_name}.service <<EOF
[Unit]
Description=AuditLoader package HTTP server
After=network.target

[Service]
Type=simple
User=$install_user
Group=$install_user
WorkingDirectory=$remote_dir
ExecStart=$python_bin -m http.server ${auditloader_http_port} --bind 0.0.0.0
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF"
    remote_exec_sudo "$leader" "systemctl daemon-reload && systemctl enable ${service_name} && systemctl restart ${service_name}"
}

create_audit_table() {
    local sql_file
    sql_file=$(mktemp /tmp/auditloader_table.XXXXXX.sql)
    cat > "$sql_file" <<EOF
CREATE DATABASE IF NOT EXISTS starrocks_audit_db__;

CREATE TABLE IF NOT EXISTS starrocks_audit_db__.starrocks_audit_tbl__ (
  \`queryId\` VARCHAR(64) COMMENT "查询的唯一ID",
  \`timestamp\` DATETIME NOT NULL COMMENT "查询开始时间",
  \`queryType\` VARCHAR(12) COMMENT "查询类型（query, slow_query, connection）",
  \`clientIp\` VARCHAR(32) COMMENT "客户端IP",
  \`user\` VARCHAR(64) COMMENT "查询用户名",
  \`authorizedUser\` VARCHAR(64) COMMENT "用户唯一标识，既user_identity",
  \`resourceGroup\` VARCHAR(64) COMMENT "资源组名",
  \`catalog\` VARCHAR(32) COMMENT "数据目录名",
  \`db\` VARCHAR(96) COMMENT "查询所在数据库",
  \`state\` VARCHAR(8) COMMENT "查询状态（EOF，ERR，OK）",
  \`errorCode\` VARCHAR(512) COMMENT "错误码",
  \`queryTime\` BIGINT COMMENT "查询执行时间（毫秒）",
  \`scanBytes\` BIGINT COMMENT "查询扫描的字节数",
  \`scanRows\` BIGINT COMMENT "查询扫描的记录行数",
  \`returnRows\` BIGINT COMMENT "查询返回的结果行数",
  \`cpuCostNs\` BIGINT COMMENT "查询CPU耗时（纳秒）",
  \`memCostBytes\` BIGINT COMMENT "查询消耗内存（字节）",
  \`stmtId\` INT COMMENT "SQL语句增量ID",
  \`isQuery\` TINYINT COMMENT "SQL是否为查询（1或0）",
  \`feIp\` VARCHAR(128) COMMENT "执行该语句的FE IP",
  \`stmt\` VARCHAR(1048576) COMMENT "SQL原始语句",
  \`digest\` VARCHAR(32) COMMENT "慢SQL指纹",
  \`planCpuCosts\` DOUBLE COMMENT "查询规划阶段CPU占用（纳秒）",
  \`planMemCosts\` DOUBLE COMMENT "查询规划阶段内存占用（字节）",
  \`pendingTimeMs\` BIGINT COMMENT "查询在队列中等待的时间（毫秒）",
  \`queryFeMemory\` BIGINT COMMENT "查询申请FE内存（字节）",
  \`candidateMVs\` VARCHAR(65533) NULL COMMENT "候选MV列表",
  \`hitMvs\` VARCHAR(65533) NULL COMMENT "命中MV列表",
  \`warehouse\` VARCHAR(32) NULL COMMENT "warehouse name"
) ENGINE = OLAP
DUPLICATE KEY (\`queryId\`, \`timestamp\`, \`queryType\`)
COMMENT "审计日志表"
PARTITION BY RANGE (\`timestamp\`) ()
DISTRIBUTED BY HASH (\`queryId\`) BUCKETS 3
PROPERTIES (
  "dynamic_partition.time_unit" = "DAY",
  "dynamic_partition.start" = "-30",
  "dynamic_partition.end" = "3",
  "dynamic_partition.prefix" = "p",
  "dynamic_partition.buckets" = "3",
  "dynamic_partition.enable" = "true",
  "replication_num" = "${auditloader_replication_num:-3}"
);
EOF

    log_info "Creating AuditLoader database and table"
    mysql_exec_file "$sql_file"
    rm -f "$sql_file"
}

create_audit_user() {
    local sql_file
    sql_file=$(mktemp /tmp/auditloader_user.XXXXXX.sql)
    cat > "$sql_file" <<EOF
CREATE USER IF NOT EXISTS '${auditloader_user}'@'%' IDENTIFIED BY '${auditloader_password}';
GRANT SELECT, INSERT ON TABLE starrocks_audit_db__.starrocks_audit_tbl__ TO USER '${auditloader_user}'@'%';
EOF

    log_info "Creating AuditLoader StarRocks user ${auditloader_user}"
    mysql_exec_file "$sql_file"
    rm -f "$sql_file"
}

install_auditloader_plugin() {
    local package=$1
    local md5sum
    local plugin_url
    local installed

    md5sum=$(md5 -q "$package" 2>/dev/null || md5sum "$package" | awk '{print $1}')
    plugin_url="http://${leader}:${auditloader_http_port}/auditloader.zip"

    installed=$(mysql_exec_silent "SHOW PLUGINS;" | awk '$1 == "AuditLoader" && $NF == "INSTALLED" { print $1 }' || true)
    if [ "$installed" = "AuditLoader" ]; then
        log_info "AuditLoader plugin already installed, skip install"
        return 0
    fi

    log_info "Installing AuditLoader plugin from $plugin_url"
    mysql_exec "INSTALL PLUGIN FROM \"${plugin_url}\" PROPERTIES(\"md5sum\" = \"${md5sum}\");"
    mysql_exec "SHOW PLUGINS;"
}

main() {
    read_hosts_config
    read_config
    read_fe_config

    if [ "${install_auditloader:-true}" != "true" ]; then
        log_info "AuditLoader installation disabled"
        exit 0
    fi

    local source_package
    local prepared_package
    source_package=$(resolve_auditloader_package)
    prepared_package=$(mktemp /tmp/auditloader-package.XXXXXX.zip)

    build_auditloader_package "$source_package" "$prepared_package"
    start_auditloader_http_service "$prepared_package"
    create_audit_table
    create_audit_user
    install_auditloader_plugin "$prepared_package"
    rm -f "$prepared_package"

    log_info "AuditLoader setup completed"
}

main "$@"
