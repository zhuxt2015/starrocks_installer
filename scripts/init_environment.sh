#!/bin/bash
###################################################
# 功能:
# 1. 将remote_init.sh脚本分发到所有主机
# 2. 在所有主机执行remote_init.sh脚本
# 3. 校验系统参数，验证初始化是否成功
###################################################
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"
source "$SCRIPT_DIR/common.sh"


remote_init() {
    host=$1
    log_info "Starting initialization on node: $host"

    # 复制初始化脚本到远程主机
    remote_exec $host "cat > /tmp/remote_init.sh" < "$remote_init_config"

    # 在远程主机上执行初始化脚本
    remote_exec "$host" "bash /tmp/remote_init.sh"

    # 清理临时文件
    # remote_exec "$host" "rm -f /tmp/remote_init.sh"

    log_info "System initialization completed on $host"
}

check_init_status() {
    local host=$1
    log_info "Checking initialization status on $host"

    # 检查项目列表
    local checks=(
        "grep 'LANG=en_US.UTF-8' /etc/locale.conf"
        "grep '* soft nofile 655350' /etc/security/limits.conf"
        "grep 'SELINUX=disabled' /etc/selinux/config"
        "cat /sys/kernel/mm/transparent_hugepage/enabled | grep '\\[never\\]'"
        "/usr/sbin/sysctl -n vm.swappiness | grep '^0$'"
        "grep 'net.ipv4.tcp_abort_on_overflow=1' /etc/sysctl.conf"
        "systemctl status firewalld | grep 'inactive'"
        "which java"
        "systemctl status ntpd | grep 'active'"
    )

    for check in "${checks[@]}"; do
        if ! remote_exec "$host" "$check" >/dev/null 2>&1; then
            log_warn "[$host] Check failed: $check"
        fi
    done
}

# 主函数
main() {
    log_info "Starting StarRocks initialization and checking process..."
    local remote_init_config="$SCRIPT_DIR/remote_init.sh"
    check_file "$remote_init_config"
    # 读取配置文件
    read_hosts_config && read_config
    sed -i "s/^repo_domain=.*/repo_domain=${repo_domain}/" "$remote_init_config"
    sed -i "s#^yum_repo_url=.*#yum_repo_url=${yum_repo_url}#" "$remote_init_config"
    sed -i "s/^ntp_server_ip=.*/ntp_server_ip=${leader}/" "$remote_init_config"
    sed -i "s/^jdk_package=.*/jdk_package=${jdk_package}/" "$remote_init_config"
    sed -i "s#^java_home=.*#java_home=${java_home}#" "$remote_init_config"

    # 对所有节点执行初始化和检查
    for node in "${host_list[@]}"; do
        log_info "Processing node: $node"
        remote_init "$node"
        check_init_status "$node"
    done

    log_info "All nodes have been processed"
}

# 执行主函数
main