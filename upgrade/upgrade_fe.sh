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
    local current_version=""
    if [ -n "$leader" ]; then
        log_info "Upgrade all ${service^^} to new version $upgrade_version"
        package_filename="StarRocks-${upgrade_version}-centos-amd64.tar.gz"
        package_filepath="${package_path%/}/$package_filename"
        download_package "$upgrade_version"
        tar_sub_dir=${package_filename%.tar.gz}
        service_path="${install_path%/}/$service"
        local commands=(
            "sudo tar xf $package_filepath -C ${install_path} ${tar_sub_dir}/$service"
            "rm -rf $service_path/lib_*"
            "rm -rf $service_path/bin_*"
            "rm -rf $service_path/spark-dpp_*"
            "mv $service_path/lib $service_path/lib_$(date +%Y%m%d%H%M%S)"
            "mv $service_path/bin $service_path/bin_$(date +%Y%m%d%H%M%S)"
            "mv $service_path/spark-dpp $service_path/spark-dpp_$(date +%Y%m%d%H%M%S)"
            "cp -r ${install_path%/}/${tar_sub_dir}/${service}/lib $service_path/"
            "cp -r ${install_path%/}/${tar_sub_dir}/${service}/bin $service_path/"
            "sudo rm -rf ${install_path%/}/${tar_sub_dir}"
        )
        local leader_ip
        local fe_ip=()
        # 获取所有FE节点ip
        get_fe_ip(){
            local result=$(mysql_command_exec_silent "show frontends;")
            if [ -n "$result" ];then
                while read line; do
                    arr=($line)
                    ip=${arr[1]}
                    role=${arr[6]}
                    if [ "$role" = "LEADER" ]; then
                      leader_ip=$ip
                    else
                      fe_ip+=($ip)
                    fi
                done <<< "$result"
                #将leader节点放到最后处理
                fe_ip+=("$leader_ip")
            fi

        }
        get_fe_ip
        # 先升级follower，再升级leader
        if [ "${#fe_ip[@]}" -gt 0 ];then
            for host in "${fe_ip[@]}"; do
                current_version=$(get_current_version "$host" "$service")
                current_version=${current_version%-*}
                if [[ "$current_version" == "$upgrade_version" ]];then
                    log_info "Skip upgrade $host ${service^^}, current version $current_version is equal to upgrade version $upgrade_version"
                    continue
                fi
                if printf "%s\n%s" "$current_version" "$upgrade_version" | sort -V | head -n1 | grep -q "^${upgrade_version}$"; then
                    log_info "Skip upgrade $host ${service^^}, current version $current_version is greater than upgrade version $upgrade_version"
                    continue
                fi
                log_info "Upgrade $host ${service^^} from version $current_version to version $upgrade_version"
                distribute_install_file "$host" "$package_filepath"
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
    mysql_command_exec "show frontends;show backends;"
}
main
