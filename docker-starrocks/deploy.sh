#!/bin/bash

# StarRocks 分布式部署脚本
# 用于在3台服务器上部署 StarRocks 存算分离集群

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 服务器配置 - 请根据实际情况修改
SERVER1_IP="192.168.1.10"
SERVER2_IP="192.168.1.11" 
SERVER3_IP="192.168.1.12"
SSH_USER="ubuntu"
SSH_KEY_PATH="~/.ssh/id_rsa"

# 项目路径
REMOTE_PATH="/opt/starrocks-cluster"

echo -e "${GREEN}=== StarRocks 分布式集群部署脚本 ===${NC}"
echo "Server1 (FE1+CN1+MinIO): $SERVER1_IP"
echo "Server2 (FE2+CN2): $SERVER2_IP"
echo "Server3 (FE3+CN3): $SERVER3_IP"
echo ""

# 检查SSH连接
check_ssh() {
    local server_ip=$1
    echo -e "${YELLOW}检查 $server_ip SSH连接...${NC}"
    if ssh -i $SSH_KEY_PATH -o ConnectTimeout=5 $SSH_USER@$server_ip "echo 'SSH连接正常'" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ $server_ip SSH连接正常${NC}"
        return 0
    else
        echo -e "${RED}✗ $server_ip SSH连接失败${NC}"
        return 1
    fi
}

# 安装Docker和Docker Compose
install_docker() {
    local server_ip=$1
    echo -e "${YELLOW}在 $server_ip 安装Docker...${NC}"
    
    ssh -i $SSH_KEY_PATH $SSH_USER@$server_ip << 'EOF'
        # 检查Docker是否已安装
        if command -v docker &> /dev/null; then
            echo "Docker已安装，跳过安装步骤"
        else
            echo "安装Docker..."
            sudo apt-get update
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
            sudo usermod -aG docker $USER
        fi
        
        # 检查Docker Compose是否已安装
        if command -v docker-compose &> /dev/null; then
            echo "Docker Compose已安装，跳过安装步骤"
        else
            echo "安装Docker Compose..."
            sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        fi
        
        # 启动Docker服务
        sudo systemctl enable docker
        sudo systemctl start docker
        
        echo "Docker安装完成"
EOF
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $server_ip Docker安装成功${NC}"
    else
        echo -e "${RED}✗ $server_ip Docker安装失败${NC}"
        exit 1
    fi
}

# 部署配置文件
deploy_config() {
    local server_ip=$1
    local server_name=$2
    
    echo -e "${YELLOW}部署配置到 $server_ip ($server_name)...${NC}"
    
    # 创建远程目录
    ssh -i $SSH_KEY_PATH $SSH_USER@$server_ip "sudo mkdir -p $REMOTE_PATH && sudo chown $SSH_USER:$SSH_USER $REMOTE_PATH"
    
    # 复制配置文件
    scp -i $SSH_KEY_PATH -r ./shared-config $SSH_USER@$server_ip:$REMOTE_PATH/
    scp -i $SSH_KEY_PATH -r ./$server_name/* $SSH_USER@$server_ip:$REMOTE_PATH/
    
    # 创建数据和日志目录
    ssh -i $SSH_KEY_PATH $SSH_USER@$server_ip << EOF
        cd $REMOTE_PATH
        mkdir -p data logs
        
        # 根据服务器创建对应的数据目录
        case "$server_name" in
            "server1")
                mkdir -p data/{minio,fe1,cn1} logs/{minio,fe1,cn1}
                ;;
            "server2") 
                mkdir -p data/{fe2,cn2} logs/{fe2,cn2}
                ;;
            "server3")
                mkdir -p data/{fe3,cn3} logs/{fe3,cn3}
                ;;
        esac
        
        # 设置权限
        chmod -R 755 data logs
EOF
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $server_ip 配置部署成功${NC}"
    else
        echo -e "${RED}✗ $server_ip 配置部署失败${NC}"
        exit 1
    fi
}

# 更新配置文件中的IP地址
update_config_ips() {
    echo -e "${YELLOW}更新配置文件中的IP地址...${NC}"
    
    # 更新FE配置
    sed -i "s/192\.168\.1\.10/$SERVER1_IP/g" shared-config/fe/fe.conf
    sed -i "s/192\.168\.1\.11/$SERVER2_IP/g" shared-config/fe/fe.conf  
    sed -i "s/192\.168\.1\.12/$SERVER3_IP/g" shared-config/fe/fe.conf
    
    # 更新CN配置
    sed -i "s/192\.168\.1\.10/$SERVER1_IP/g" shared-config/cn/cn.conf
    sed -i "s/192\.168\.1\.11/$SERVER2_IP/g" shared-config/cn/cn.conf
    sed -i "s/192\.168\.1\.12/$SERVER3_IP/g" shared-config/cn/cn.conf
    
    # Docker Compose 文件使用 host 网络模式，无需修改IP配置
    
    echo -e "${GREEN}✓ IP地址更新完成${NC}"
}

# 启动服务
start_services() {
    local server_ip=$1
    local server_name=$2
    
    echo -e "${YELLOW}在 $server_ip 启动服务...${NC}"
    
    ssh -i $SSH_KEY_PATH $SSH_USER@$server_ip << EOF
        cd $REMOTE_PATH
        
        # 拉取镜像
        docker-compose pull
        
        # 启动服务
        docker-compose up -d
        
        # 等待服务启动
        sleep 10
        
        # 检查服务状态
        docker-compose ps
EOF
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $server_ip 服务启动成功${NC}"
    else
        echo -e "${RED}✗ $server_ip 服务启动失败${NC}"
        exit 1
    fi
}

# 初始化集群
init_cluster() {
    echo -e "${YELLOW}初始化StarRocks集群...${NC}"
    
    # 等待FE Leader启动
    echo "等待FE Leader启动..."
    sleep 60
    
    # 在server1上执行集群初始化
    ssh -i $SSH_KEY_PATH $SSH_USER@$SERVER1_IP << EOF
        cd $REMOTE_PATH
        
        # 等待FE Leader就绪
        echo "等待FE Leader就绪..."
        while ! docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "SHOW FRONTENDS;" 2>/dev/null; do
            echo "等待FE Leader就绪..."
            sleep 10
        done
        
        echo "FE Leader已就绪，开始添加节点..."
        
        # 添加FE Follower节点
        docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD FOLLOWER '$SERVER2_IP:9010';" || true
        docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD FOLLOWER '$SERVER3_IP:9010';" || true
        
        # 等待FE节点同步
        sleep 30
        
        # 添加CN节点
        docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD COMPUTE NODE '$SERVER1_IP:9050';" || true
        docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD COMPUTE NODE '$SERVER2_IP:9050';" || true
        docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD COMPUTE NODE '$SERVER3_IP:9050';" || true
        
        # 等待节点注册
        sleep 30
        
        # 配置MinIO
        docker exec minio mc alias set local http://localhost:9000 minioadmin minioadmin123
        docker exec minio mc mb local/starrocks-data || true
        docker exec minio mc policy set public local/starrocks-data
        
        # 创建存储卷
        docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "
        CREATE STORAGE VOLUME starrocks_storage_volume
        TYPE = S3
        LOCATIONS = ('s3://starrocks-data/')
        PROPERTIES (
            'aws.s3.region' = 'us-east-1',
            'aws.s3.endpoint' = 'http://$SERVER1_IP:9000',
            'aws.s3.use_aws_sdk_default_behavior' = 'false',
            'aws.s3.use_instance_profile' = 'false',
            'aws.s3.access_key' = 'minioadmin',
            'aws.s3.secret_key' = 'minioadmin123',
            'aws.s3.enable_ssl' = 'false',
            'aws.s3.enable_path_style_access' = 'true'
        );" || true
        
        echo "集群初始化完成"
EOF
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 集群初始化成功${NC}"
    else
        echo -e "${RED}✗ 集群初始化失败${NC}"
        exit 1
    fi
}

# 检查集群状态
check_cluster() {
    echo -e "${YELLOW}检查集群状态...${NC}"
    
    ssh -i $SSH_KEY_PATH $SSH_USER@$SERVER1_IP << EOF
        cd $REMOTE_PATH
        
        echo "=== FE节点状态 ==="
        docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "SHOW FRONTENDS;"
        
        echo "=== CN节点状态 ==="
        docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "SHOW COMPUTE NODES;"
        
        echo "=== 存储卷状态 ==="
        docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "SHOW STORAGE VOLUMES;"
EOF
}

# 主函数
main() {
    echo -e "${GREEN}开始部署StarRocks分布式集群...${NC}"
    
    # 检查参数
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo "用法: $0 [选项]"
        echo "选项:"
        echo "  --check-only    仅检查SSH连接"
        echo "  --install-only  仅安装Docker"
        echo "  --deploy-only   仅部署配置"
        echo "  --start-only    仅启动服务"
        echo "  --init-only     仅初始化集群"
        echo "  --help, -h      显示帮助信息"
        exit 0
    fi
    
    # 更新配置文件IP
    update_config_ips
    
    # 检查SSH连接
    if [ "$1" != "--deploy-only" ] && [ "$1" != "--start-only" ] && [ "$1" != "--init-only" ]; then
        check_ssh $SERVER1_IP || exit 1
        check_ssh $SERVER2_IP || exit 1  
        check_ssh $SERVER3_IP || exit 1
        
        if [ "$1" = "--check-only" ]; then
            echo -e "${GREEN}SSH连接检查完成${NC}"
            exit 0
        fi
    fi
    
    # 安装Docker
    if [ "$1" != "--deploy-only" ] && [ "$1" != "--start-only" ] && [ "$1" != "--init-only" ]; then
        install_docker $SERVER1_IP
        install_docker $SERVER2_IP
        install_docker $SERVER3_IP
        
        if [ "$1" = "--install-only" ]; then
            echo -e "${GREEN}Docker安装完成${NC}"
            exit 0
        fi
    fi
    
    # 部署配置
    if [ "$1" != "--start-only" ] && [ "$1" != "--init-only" ]; then
        deploy_config $SERVER1_IP "server1"
        deploy_config $SERVER2_IP "server2"
        deploy_config $SERVER3_IP "server3"
        
        if [ "$1" = "--deploy-only" ]; then
            echo -e "${GREEN}配置部署完成${NC}"
            exit 0
        fi
    fi
    
    # 启动服务
    if [ "$1" != "--init-only" ]; then
        start_services $SERVER1_IP "server1"
        sleep 20
        start_services $SERVER2_IP "server2"  
        sleep 20
        start_services $SERVER3_IP "server3"
        
        if [ "$1" = "--start-only" ]; then
            echo -e "${GREEN}服务启动完成${NC}"
            exit 0
        fi
    fi
    
    # 初始化集群
    init_cluster
    
    # 检查集群状态
    check_cluster
    
    echo -e "${GREEN}=== 部署完成 ===${NC}"
    echo "FE Leader Web UI: http://$SERVER1_IP:8030"
    echo "FE2 Web UI: http://$SERVER2_IP:8030"
    echo "FE3 Web UI: http://$SERVER3_IP:8030"
    echo "MinIO Console: http://$SERVER1_IP:9001 (minioadmin/minioadmin123)"
    echo "MySQL连接: mysql -h$SERVER1_IP -P9030 -uroot"
}

# 执行主函数
main "$@"