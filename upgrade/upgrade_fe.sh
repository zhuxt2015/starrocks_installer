#!/bin/bash
###################################################
# 功能:升级所有FE服务
###################################################
set -eu

main() {
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../scripts/log.sh"
    source "$SCRIPT_DIR/../scripts/common.sh"

    read_config
    read_fe_config
    local service="fe"
    if [ -n "$leader" ]; then
        log_info "Upgrade FE to version $upgrade_version"
        package_filename="StarRocks-${upgrade_version}-centos-amd64.tar.gz"
        package_filepath="${package_path%/}/$package_filename"
        download_package "$upgrade_version"
        tar_sub_dir=${package_filename%.tar.gz}
        local commands=(
            "tar xf $package_filepath -C ${install_path} ${tar_sub_dir}/$service"
            "true; cd ${install_path%/}/$service && rm -rf lib_* && mv lib lib_$(date +%Y%m%d%H%M%S) && rm -rf bin_* && mv bin bin_$(date +%Y%m%d%H%M%S) && rm -rf spark-dpp_* && mv spark-dpp spark-dpp_$(date +%Y%m%d%H%M%S) && cp -r ${install_path%/}/${tar_sub_dir}/${service}/lib .&&cp -r ${install_path%/}/${tar_sub_dir}/${service}/bin ."
            "rm -rf ${install_path%/}/${tar_sub_dir}"
        )
        # 先升级follower
        if [ -n "$follower" ];then
            IFS=',' read -ra FRONTENDS <<< "$follower"
            for host in "${FRONTENDS[@]}"; do
                distribute_install_file "$host" "$package_filepath"
                stop_service "$host" "$service"
                loop_remote_exec "$host" "${commands[@]}"
                start_service "$host" "$service"
                check_service_status "$host" "$service"
            done
        fi
        #升级leader
        stop_service "$leader" "$service"
        loop_remote_exec "$leader" "${commands[@]}"
        start_service "$leader" "$service"
        check_service_status "$leader" "$service"
    fi
    #打印集群信息
    mysql_command_exec "show frontends;show backends;"
}
main
