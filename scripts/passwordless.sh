#!/bin/bash
###################################################
# 功能:
# 1. 如果install_user不存在，则创建用户
# 2. 主节install_user点对其他节点免密
# 3. install_user拥有sudo权限
###################################################
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"
source "$SCRIPT_DIR/common.sh"

# 检查并创建主节点install_user的SSH密钥
check_main_node_ssh_key() {
    local main_node=$1
    local user=$2
    local password=$3
    local use_sudo=$4
    local root_password=$5
    local install_user=$6
    local port=${7:-22}

    if [ "$(hostname -I | awk '{print $1}')" = "$main_node" ]; then
        # 当前节点就是主节点
        if ! sudo test -f "/home/$install_user/.ssh"; then
            log_warn "Creating .ssh directory for $install_user..."
            sudo mkdir -p "/home/$install_user/.ssh"
            sudo chmod 700 "/home/$install_user/.ssh"
            sudo chown "$install_user:$install_user" "/home/$install_user/.ssh"
        fi

        if ! sudo test -f "/home/$install_user/.ssh/id_rsa"; then
            log_warn "SSH key not found for $install_user, generating..."
            sudo -u "$install_user" ssh-keygen -t rsa -N "" -f "/home/$install_user/.ssh/id_rsa" || {
                log_error "Failed to generate SSH key for $install_user"
                exit 1
            }
            log_info "SSH key generated successfully for $install_user"
        else
            log_info "SSH key already exists for $install_user"
        fi
        #生成指纹添加到known_hosts
        if ! grep "$main_node" /home/$install_user/.ssh/known_hosts;then
            sudo -u "$install_user" ssh-keyscan -H "$main_node" | sudo tee -a "/home/$install_user/.ssh/known_hosts" 2>/dev/null
        fi
        PUB_KEY=$(sudo -u "$install_user" cat "/home/$install_user/.ssh/id_rsa.pub")
    else
        # 从远程主节点获取install_user的公钥
        log_warn "Retrieving SSH public key from main node's $install_user..."
        
        if [ "$use_sudo" = "true" ] && [ -n "$password" ]; then
            # 使用sudo模式
            PUB_KEY=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$user@$main_node" "
                sudo mkdir -p /home/$install_user/.ssh 2>/dev/null
                sudo chmod 700 /home/$install_user/.ssh
                sudo chown $install_user:$install_user /home/$install_user/.ssh
                if ! sudo test -f /home/$install_user/.ssh/id_rsa ; then
                    sudo -u $install_user ssh-keygen -t rsa -N \"\" -f /home/$install_user/.ssh/id_rsa
                fi
                sudo cat /home/$install_user/.ssh/id_rsa.pub
            ")
        elif [ -n "$root_password" ]; then
            # 使用root模式，使用sshpass
            PUB_KEY=$(sshpass -p "$root_password" ssh -o StrictHostKeyChecking=no -p "$port" "root@$main_node" "
                if ! sudo test -f /home/$install_user/.ssh/id_rsa ; then
                    su - $install_user -c 'ssh-keygen -t rsa -N \"\" -f /home/$install_user/.ssh/id_rsa'
                fi
                cat /home/$install_user/.ssh/id_rsa.pub
            ")
        else
            log_error "Neither sudo password nor root password provided for main node"
            exit 1
        fi

        if [ -z "$PUB_KEY" ]; then
            log_error "Failed to retrieve SSH public key from main node's $install_user"
            exit 1
        fi
        log_info "Successfully retrieved SSH public key from main node's $install_user"
    fi
}

# 检查是否安装 sshpass
check_sshpass() {
    if ! command -v sshpass &> /dev/null; then
        log_error "sshpass is not installed. Please install it before running the script."
        exit 1
    fi
}

# 检查主节点 install_user 是否对从节点 install_user 免密
check_main_node_passwordless() {
    local main_node=$1
    local worker_node=$2
    local install_user=$3

    if [ "$(hostname -I | awk '{print $1}')" = "$main_node" ]; then
        # 在主节点上执行，直接用install_user测试
        sudo -u "$install_user" ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$install_user@$worker_node" "exit" &>/dev/null
    fi

    if [ $? -eq 0 ]; then
        log_info "Passwordless SSH is already set up from $install_user@$main_node to $install_user@$worker_node"
        return 0
    else
        log_warn "Passwordless SSH is NOT set up from $install_user@$main_node to $install_user@$worker_node, proceeding with configuration."
        return 1
    fi
}

# 配置单台服务器
setup_server() {
    local host=$1
    local port=$2
    local user=$3
    local password=$4
    local root_password=$5
    local use_sudo=$6
    local install_user=$7
    local main_node=$8
    PUB_KEY=""

    echo -e "\nConfiguring server: $host"
    if check_main_node_passwordless "$main_node" "$host" "$install_user"; then
       return 0
    fi
    if [ "$use_sudo" = "true" ] && [ -n "$password" ]; then
        echo "Using sudo mode for $host"
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$user@$host" "sudo /usr/sbin/useradd -m $install_user 2>/dev/null || true"
        # 确保我们有主节点install_user的公钥
        if [ -z "$PUB_KEY" ]; then
            check_main_node_ssh_key "$main_node" "$user" "$password" "$use_sudo" "$root_password" "$install_user" "$port"
        fi
        local commands="sudo mkdir -p /home/$install_user/.ssh && \
    echo '$PUB_KEY' |sudo tee /home/$install_user/.ssh/authorized_keys && \
    sudo chown -R $install_user:$install_user /home/$install_user/.ssh && \
    sudo chmod 700 /home/$install_user/.ssh && \
    sudo chmod 600 /home/$install_user/.ssh/authorized_keys && \
    echo '$install_user ALL=(ALL) NOPASSWD: ALL' |sudo tee -a /etc/sudoers &>/dev/null"
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$user@$host" "$commands"

    elif [ "$use_sudo" = "false" ] && [ -n "$root_password" ]; then
        echo "Using root mode for $host"
        sshpass -p "$root_password" ssh -o StrictHostKeyChecking=no -p "$port" "root@$host" "sudo /usr/sbin/useradd -m $install_user 2>/dev/null || true"
        # 确保我们有主节点install_user的公钥
        if [ -z "$PUB_KEY" ]; then
            check_main_node_ssh_key "$main_node" "$user" "$password" "$use_sudo" "$root_password" "$install_user" "$port"
        fi
        local commands="sudo mkdir -p /home/$install_user/.ssh && \
    echo '$PUB_KEY' |sudo tee /home/$install_user/.ssh/authorized_keys && \
    sudo chown -R $install_user:$install_user /home/$install_user/.ssh && \
    sudo chmod 700 /home/$install_user/.ssh && \
    sudo chmod 600 /home/$install_user/.ssh/authorized_keys && \
    echo '$install_user ALL=(ALL) NOPASSWD: ALL' |sudo tee -a /etc/sudoers &>/dev/null"
        sshpass -p "$root_password" ssh -o StrictHostKeyChecking=no -p "$port" "root@$host" "$commands"
    else
        log_error "Neither sudo password nor root password provided for $host"
        exit 1
    fi
}

# 主函数
main() {

    read_config
    read_hosts_config
    check_sshpass

    # 处理所有服务器
    for host in "${host_list[@]}"; do
        log_info "Processing server: $host"
        
        # 获取该服务器的配置
        port="${server_configs[${host}_port]}"
        user="${server_configs[${host}_user]}"
        password="${server_configs[${host}_password]}"
        root_password="${server_configs[${host}_root_password]}"
        use_sudo="${server_configs[${host}_use_sudo]}"
        
        log_info "Using configuration:"
        echo "Port: $port"
        echo "User: $user"
        echo "Use Sudo: $use_sudo"
        
        setup_server "$host" "$port" "$user" "$password" "$root_password" "$use_sudo" "$install_user" "$main_node"
    done
}

main "$@"