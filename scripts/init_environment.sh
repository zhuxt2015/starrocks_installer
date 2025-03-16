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

    log_info "All nodes have been initialized"
}

# 执行主函数
main