#!/bin/bash
###################################################
# 功能:降级所有FE服务
###################################################
set -eu

leader_ip=""
fe_ip=()

main() {
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../scripts/log.sh"
    source "$SCRIPT_DIR/../scripts/common.sh"

    read_config
    read_fe_config
    local service="fe"
    local current_version=""
    if [ -n "$leader" ]; then
        log_info "Downgrade all ${service^^} to new version $downgrade_version"
        package_filename="StarRocks-${upgrade_version}-centos-amd64.tar.gz"
        package_filepath="${package_path%/}/$package_filename"
        download_package "$downgrade_version"
        tar_sub_dir=${package_filename%.tar.gz}
        service_path="${install_path%/}/$service"
        local commands=(
            "sudo tar xf $package_filepath -C ${install_path} ${tar_sub_dir}/$service"
            "rm -rf $service_path/lib_*"
            "rm -rf $service_path/bin_*"
            "rm -rf $service_path/spark-dpp_*"
            "if [ -d $service_path/lib ];then mv $service_path/lib $service_path/lib_$(date +%Y%m%d%H%M%S); fi"
            "if [ -d $service_path/bin ];then mv $service_path/bin $service_path/bin_$(date +%Y%m%d%H%M%S); fi"
            "if [ -d $service_path/spark-dpp ];then mv $service_path/spark-dpp $service_path/spark-dpp_$(date +%Y%m%d%H%M%S); fi"
            "cp -r ${install_path%/}/${tar_sub_dir}/${service}/lib $service_path/"
            "cp -r ${install_path%/}/${tar_sub_dir}/${service}/bin $service_path/"
            "cp -r ${install_path%/}/${tar_sub_dir}/${service}/spark-dpp $service_path/"
            "sudo rm -rf ${install_path%/}/${tar_sub_dir}"
        )

        get_fe_ip
        # 先升级follower，再升级leader
        if [ "${#fe_ip[@]}" -gt 0 ];then
            for host in "${fe_ip[@]}"; do
                current_version=$(get_current_version "$host" "$service")
                current_version=${current_version%-*}
                if ! check_downgrade_version "$current_version" "$downgrade_version"; then
                    continue
                fi
                log_info "Downgrade $host ${service^^} from version $current_version to version $downgrade_version"
                distribute_install_file "$host"
                stop_service "$host" "$service"
                # 备份和替换文件
                log_info "Backup and replace ${service^^} files on $host"
                loop_remote_exec "$host" "${commands[@]}"
                start_service "$host" "$service"
                check_service_status "$host" "$service"
            done
        fi
    fi
    #打印集群信息
    log_info "StarRocks cluster information:"
    mysql_command_exec "show frontends;"
}
main
