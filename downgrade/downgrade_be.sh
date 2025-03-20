#!/bin/bash
###################################################
# 功能:降级所有BE服务
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
        log_info "Downgrade all ${service^^} to new version $downgrade_version"
        package_filename="StarRocks-${upgrade_version}-centos-amd64.tar.gz"
        package_filepath="${package_path%/}/$package_filename"
        download_package "$downgrade_version"
        pre_command=$(cat <<EOF
ADMIN SET FRONTEND CONFIG ("tablet_sched_max_scheduling_tablets" = "0");
ADMIN SET FRONTEND CONFIG ("tablet_sched_max_balancing_tablets" = "0");
ADMIN SET FRONTEND CONFIG ("disable_balance" = "true");
ADMIN SET FRONTEND CONFIG ("disable_colocate_balance" = "true");
EOF
)
        mysql_command_exec "$pre_command"
        IFS=',' read -ra BACKENDS <<< "$backend"
        for host in "${BACKENDS[@]}"; do
            local current_version=$(get_current_version "$host" "$service")
            current_version=${current_version%-*}
            if ! check_downgrade_version "$current_version" "$downgrade_version"; then
                continue
            fi
            log_info "Downgrade $host ${service^^} from version $current_version to version $downgrade_version"
            distribute_install_file "$host"
            stop_service "$host" "$service"
            tar_sub_dir=${package_filename%.tar.gz}
            service_path="${install_path%/}/$service"
            # 备份和替换文件
            log_info "Backup and replace ${service^^} files on $host"
            local commands=(
                "sudo tar xf $package_filepath -C ${install_path} ${tar_sub_dir}/$service"
                "rm -rf $service_path/lib_*"
                "rm -rf $service_path/bin_*"
                "mv $service_path/lib $service_path/lib_$(date +%Y%m%d%H%M%S)"
                "mv $service_path/bin $service_path/bin_$(date +%Y%m%d%H%M%S)"
                "cp -r ${install_path%/}/${tar_sub_dir}/${service}/lib $service_path/"
                "cp -r ${install_path%/}/${tar_sub_dir}/${service}/bin $service_path/"
                "sudo rm -rf ${install_path%/}/${tar_sub_dir}"
            )
            loop_remote_exec "$host" "${commands[@]}"
            start_service "$host" "$service"
            check_service_status "$host" "$service"
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
    log_info "StarRocks ${service^^} cluster information:"
    mysql_command_exec "show frontends;show backends;"
}
main
