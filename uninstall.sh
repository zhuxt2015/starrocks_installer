#!/bin/bash
###################################################
# 功能:
# 1. 停止所有服务
# 2. 删除所有安装包
# 3. 删除存储路径、日志路径、安装路径
# 4. 删除安装用户
###################################################

set -eu
source "scripts/log.sh"
source "scripts/common.sh"

# 远程执行命令的函数
sudo_remote_exec() {
    local host=$1
    local port=$2
    local user=$3
    local password=$4
    local root_password=$5
    local use_sudo=$6
    local install_user=$7
    local cmd=$8
    if [ "$use_sudo" = "true" ] && [ -n "$password" ]; then
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$user@$host" "sudo $cmd 2>/dev/null"
    elif [ "$use_sudo" = "false" ] && [ -n "$root_password" ]; then
        sshpass -p "$root_password" ssh -o StrictHostKeyChecking=no -p "$port" "root@$host" "$cmd 2>/dev/null"
    else
        log_error "Neither sudo password nor root password provided for $host"
        exit 1
    fi
}

delete_directory() {
    local host=$1
    local path=$2
    log_info "Deleting directory $path on $host"
    if  check_directory_exists "$host" "$path";then
        remote_exec_sudo "$host" "rm -rf $path"
    fi
}

main() {
    read_hosts_config
    read_config

    # 停止FE服务
    if [ -n "$leader" ]; then
        local frontend_hosts=()
        frontend_hosts+=("$leader")
        if [ -n "$follower" ];then
            IFS=',' read -ra FOLLOWERS <<< "$follower"
            frontend_hosts+=("${FOLLOWERS[@]}")
        fi
        for frontend_host in "${frontend_hosts[@]}"; do
            stop_service "$frontend_host" "fe"
            # 删除部署路径
            delete_directory "$frontend_host" "$install_path"
            # 删除所有配置路径
            for key in "${!fe_configs[@]}"; do
                value="${fe_configs[$key]}"
                if [[ -n "$value" ]] && [[ ${key,,} =~ .*_dir$ ]]; then
                    delete_directory "$frontend_host" "$value"
                fi
            done
            # 删除安装包
            # delete_directory "$frontend_host" "$install_package"
        done
    fi
    # 停止BE服务
    if [ -n "$backend" ]; then
        read_be_config
        IFS=',' read -ra BACKENDS <<< "$backend"
        for backend_host in "${BACKENDS[@]}"; do
            stop_service "$backend_host" "be"
            for key in "${!be_configs[@]}"; do
                value="${be_configs[$key]}"
                if [[ -n "$value" ]];then
                    if [[ $key =~ .*_dir$ ]]; then
                        delete_directory "$backend_host" "$value"
                    # 处理storage_root_path
                    elif [[ "$key" == "storage_root_path" ]];then
                        IFS=';' read -ra storage_path <<< "$value"
                        for path in "${storage_path[@]}"; do
                            if [[ "$path" == *","* ]]; then
                                path=$(echo "$path" | cut -d',' -f1)
                                delete_directory "$backend_host" "$path"
                            fi
                        done
                    fi
                fi
            done
            # 删除部署路径
            delete_directory "$backend_host" "$install_path"
            # 删除安装包
            # delete_directory "$backend_host" "$install_package"
        done
    fi
    for host in "${host_list[@]}"; do
        log_info "Deleting user $install_user on $host"

        # 获取该服务器的配置
        port="${server_configs[${host}_port]}"
        user="${server_configs[${host}_user]}"
        password="${server_configs[${host}_password]}"
        root_password="${server_configs[${host}_root_password]}"
        use_sudo="${server_configs[${host}_use_sudo]}"
        # 删除安装用户
        sudo_remote_exec "$host" "$port" "$user" "$password" "$root_password" "$use_sudo" "$install_user" "/usr/sbin/userdel -r $install_user" || true
    done
    log_info "StarRocks uninstallation completed successfully"
}

# 执行主函数
main