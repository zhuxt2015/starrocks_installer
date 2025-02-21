#!/bin/bash
###################################################
# 功能:升级所有BE服务
###################################################
set -eu

main() {
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../scripts/log.sh"
    source "$SCRIPT_DIR/../scripts/common.sh"

    read_config
    read_fe_config
    read_be_config
    local service="be"
    if [ -n "$backend" ]; then
        log_info "Upgrade BE to version $upgrade_version"
        package_filename="StarRocks-${upgrade_version}-centos-amd64.tar.gz"
        package_filepath="${package_path%/}/$package_filename"
        download_package "$upgrade_version"
        pre_command=$(cat <<EOF
ADMIN SET FRONTEND CONFIG ("tablet_sched_max_scheduling_tablets" = "0");
ADMIN SET FRONTEND CONFIG ("tablet_sched_max_balancing_tablets" = "0");
ADMIN SET FRONTEND CONFIG ("disable_balance" = "true");
ADMIN SET FRONTEND CONFIG ("disable_colocate_balance" = "true");
EOF
            )
        mysql_command_exec "$pre_command"
        IFS=',' read -ra BACKENDS <<< "$backend"
        for backend_host in "${BACKENDS[@]}"; do

            distribute_install_file "$backend_host" "$package_filepath"
            stop_service "$backend_host" "$service"
            tar_sub_dir=${package_filename%.tar.gz}
            local commands=(
                "tar xf $package_filepath -C ${install_path} ${tar_sub_dir}/$service"
                "true; cd ${install_path%/}/$service && rm -rf lib_* && mv lib lib_$(date +%Y%m%d%H%M%S)&& rm -rf bin_* && mv bin bin_$(date +%Y%m%d%H%M%S) && cp -r ${install_path%/}/${tar_sub_dir}/${service}/lib .&&cp -r ${install_path%/}/${tar_sub_dir}/${service}/bin ."
                "rm -rf ${install_path%/}/${tar_sub_dir}"
            )
            loop_remote_exec "$backend_host" "${commands[@]}"
            start_service "$backend_host" "$service"
            check_service_status "$backend_host" "$service"
        done
        after_command=$(cat <<EOF
ADMIN SET FRONTEND CONFIG ("tablet_sched_max_scheduling_tablets" = "10000");
ADMIN SET FRONTEND CONFIG ("tablet_sched_max_balancing_tablets" = "500");
ADMIN SET FRONTEND CONFIG ("disable_balance" = "false");
ADMIN SET FRONTEND CONFIG ("disable_colocate_balance" = "false");
EOF
)
        mysql_command_exec "$after_command"
    fi
    #打印集群信息
    mysql_command_exec "show backends;"
}
main
