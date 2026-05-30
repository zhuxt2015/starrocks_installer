# StarRocks 3.3.17 分布式存算分离部署 (Host 网络模式)

> 🚀 基于 3台服务器的 StarRocks 存算分离架构分布式部署方案，使用 Docker Host 网络模式

## 架构设计

### 服务器分布
| 服务器 | 组件 | IP地址 | 端口 |
|--------|------|--------|------|
| Server1 | FE1(Leader) + CN1 + MinIO | 192.168.1.10 | FE:8030,9030,9020,9010 CN:8040,9060,8060,9050 MinIO:9000,9001 |
| Server2 | FE2(Follower) + CN2 | 192.168.1.11 | FE:8030,9030,9020,9010 CN:8040,9060,8060,9050 |
| Server3 | FE3(Follower) + CN3 | 192.168.1.12 | FE:8030,9030,9020,9010 CN:8040,9060,8060,9050 |

### Host 网络模式优势
- **性能最优**: 无网络转发损耗，直接使用宿主机网络栈
- **配置简单**: 无需复杂的网络配置和端口映射
- **通信直接**: 容器间通信直接使用服务器IP，无需服务发现
- **运维友好**: 网络问题排查更简单，与传统部署方式一致

## 系统要求

- **操作系统**: Ubuntu 22.04 LTS
- **硬件配置**: 每台服务器 32GB内存 + 8核CPU + 100GB磁盘
- **网络**: 服务器间网络互通，建议千兆网络
- **软件**: Docker 20.10+ 和 Docker Compose 2.0+
- **端口**: 确保以下端口在防火墙中开放

### 端口规划
| 服务 | 端口 | 说明 |
|------|------|------|
| FE | 8030 | HTTP 服务端口 |
| FE | 9030 | MySQL 协议端口 |
| FE | 9020 | Thrift RPC 端口 |
| FE | 9010 | 集群内部通信端口 |
| CN | 8040 | HTTP 服务端口 |
| CN | 9060 | Thrift RPC 端口 |
| CN | 8060 | BRPC 端口 |
| CN | 9050 | 心跳服务端口 |
| MinIO | 9000 | S3 API 端口 |
| MinIO | 9001 | Web 控制台端口 |

## 快速部署

### 1. 准备工作

```bash
# 克隆或下载项目
git clone <repository>
cd docker-starrocks

# 修改部署脚本中的服务器IP
vim deploy.sh
# 修改以下变量为实际IP:
# SERVER1_IP="192.168.1.10"
# SERVER2_IP="192.168.1.11" 
# SERVER3_IP="192.168.1.12"
# SSH_USER="ubuntu"
# SSH_KEY_PATH="~/.ssh/id_rsa"
```

### 2. 配置防火墙

在每台服务器上开放必要端口：

```bash
# Ubuntu/Debian
sudo ufw allow 8030,8040,9000,9001,9010,9020,9030,9050,9060,8060/tcp

# CentOS/RHEL
sudo firewall-cmd --permanent --add-port=8030/tcp
sudo firewall-cmd --permanent --add-port=8040/tcp
sudo firewall-cmd --permanent --add-port=9000/tcp
sudo firewall-cmd --permanent --add-port=9001/tcp
sudo firewall-cmd --permanent --add-port=9010/tcp
sudo firewall-cmd --permanent --add-port=9020/tcp
sudo firewall-cmd --permanent --add-port=9030/tcp
sudo firewall-cmd --permanent --add-port=9050/tcp
sudo firewall-cmd --permanent --add-port=9060/tcp
sudo firewall-cmd --permanent --add-port=8060/tcp
sudo firewall-cmd --reload
```

### 3. 一键部署

```bash
# 完整部署
./deploy.sh

# 分步部署
./deploy.sh --check-only    # 仅检查SSH连接
./deploy.sh --install-only  # 仅安装Docker
./deploy.sh --deploy-only   # 仅部署配置
./deploy.sh --start-only    # 仅启动服务
./deploy.sh --init-only     # 仅初始化集群
```

### 4. 验证部署

```bash
# 连接到集群
mysql -h192.168.1.10 -P9030 -uroot

# 检查集群状态
SHOW FRONTENDS;
SHOW COMPUTE NODES;
SHOW STORAGE VOLUMES;
```

## 手动部署步骤

### 1. 在每台服务器安装Docker

```bash
# 在每台服务器执行
sudo apt-get update
sudo apt-get install -y docker.io docker-compose
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
```

### 2. 部署配置文件

```bash
# Server1
scp -r shared-config server1/* user@192.168.1.10:/opt/starrocks-cluster/

# Server2  
scp -r shared-config server2/* user@192.168.1.11:/opt/starrocks-cluster/

# Server3
scp -r shared-config server3/* user@192.168.1.12:/opt/starrocks-cluster/
```

### 3. 启动服务

```bash
# 在每台服务器执行
cd /opt/starrocks-cluster
docker-compose up -d
```

### 4. 初始化集群

```bash
# 在Server1执行
# 等待FE Leader启动
sleep 60

# 添加FE节点
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD FOLLOWER '192.168.1.11:9010';"
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD FOLLOWER '192.168.1.12:9010';"

# 添加CN节点
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD COMPUTE NODE '192.168.1.10:9050';"
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD COMPUTE NODE '192.168.1.11:9050';"
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD COMPUTE NODE '192.168.1.12:9050';"

# 配置存储卷
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "
CREATE STORAGE VOLUME starrocks_storage_volume
TYPE = S3
LOCATIONS = ('s3://starrocks-data/')
PROPERTIES (
    'aws.s3.region' = 'us-east-1',
    'aws.s3.endpoint' = 'http://192.168.1.10:9000',
    'aws.s3.use_aws_sdk_default_behavior' = 'false',
    'aws.s3.use_instance_profile' = 'false',
    'aws.s3.access_key' = 'minioadmin',
    'aws.s3.secret_key' = 'minioadmin123',
    'aws.s3.enable_ssl' = 'false',
    'aws.s3.enable_path_style_access' = 'true'
);"
```

## Host 网络模式配置说明

### 网络配置
- 使用 `network_mode: host`，容器直接使用宿主机网络
- 无需端口映射，服务直接监听在宿主机端口上
- 容器间通信直接使用服务器IP地址

### 优势
1. **性能最佳**: 无网络虚拟化开销
2. **配置简单**: 无需复杂的网络配置
3. **调试方便**: 网络问题排查更直观
4. **兼容性好**: 与物理部署方式一致

### 注意事项
1. **端口冲突**: 确保宿主机端口未被占用
2. **防火墙**: 需要开放相应端口
3. **安全性**: 容器可以访问宿主机网络

## 运维管理

### 服务管理

```bash
# 启动集群 (在每台服务器执行)
docker-compose up -d

# 停止集群 (在每台服务器执行)
docker-compose down

# 重启服务
docker-compose restart

# 查看日志
docker-compose logs -f [service_name]
```

### 集群管理

```bash
# 连接到集群
mysql -h192.168.1.10 -P9030 -uroot

# 查看集群状态
SHOW FRONTENDS;
SHOW COMPUTE NODES;

# 添加CN节点 (假设新增Server4)
ALTER SYSTEM ADD COMPUTE NODE '192.168.1.13:9050';

# 删除CN节点
ALTER SYSTEM DROP COMPUTE NODE '192.168.1.13:9050';
```

### 监控检查

```bash
# 检查FE状态
curl http://192.168.1.10:8030/api/health
curl http://192.168.1.11:8030/api/health  
curl http://192.168.1.12:8030/api/health

# 检查CN状态
curl http://192.168.1.10:8040/api/health
curl http://192.168.1.11:8040/api/health
curl http://192.168.1.12:8040/api/health

# 检查MinIO状态
curl http://192.168.1.10:9000/minio/health/live
```

### 网络连通性测试

```bash
# 测试FE端口连通性
telnet 192.168.1.10 9010
telnet 192.168.1.11 9010
telnet 192.168.1.12 9010

# 测试CN端口连通性
telnet 192.168.1.10 9050
telnet 192.168.1.11 9050
telnet 192.168.1.12 9050

# 测试MinIO连通性
telnet 192.168.1.10 9000
```

## 故障排除

### 常见问题

1. **端口被占用**
   ```bash
   # 检查端口占用
   sudo netstat -tlnp | grep :8030
   sudo lsof -i :8030
   
   # 停止占用端口的进程
   sudo kill -9 <PID>
   ```

2. **防火墙阻止连接**
   ```bash
   # 检查防火墙状态
   sudo ufw status
   sudo firewall-cmd --list-all
   
   # 临时关闭防火墙测试
   sudo ufw disable
   sudo systemctl stop firewalld
   ```

3. **容器无法启动**
   ```bash
   # 查看容器日志
   docker logs starrocks-fe1
   docker logs starrocks-cn1
   
   # 检查资源使用
   docker stats
   ```

### 性能优化

1. **网络优化**
   - 使用千兆网络连接
   - 调整网络缓冲区大小
   - 启用网络压缩

2. **系统优化**
   ```bash
   # 调整系统参数
   echo 'net.core.rmem_max = 134217728' >> /etc/sysctl.conf
   echo 'net.core.wmem_max = 134217728' >> /etc/sysctl.conf
   echo 'net.ipv4.tcp_rmem = 4096 65536 134217728' >> /etc/sysctl.conf
   echo 'net.ipv4.tcp_wmem = 4096 65536 134217728' >> /etc/sysctl.conf
   sysctl -p
   ```

## 扩容指南

### 添加CN节点

1. 准备新服务器并安装Docker
2. 部署CN配置文件
3. 启动CN服务
4. 在FE中注册新CN节点

```bash
# 在新服务器启动CN
docker-compose up -d cn

# 在FE中添加CN节点
mysql -h192.168.1.10 -P9030 -uroot -e "ALTER SYSTEM ADD COMPUTE NODE 'new_server_ip:9050';"
```

### 添加FE节点

1. 部署FE配置文件到新服务器
2. 启动FE服务
3. 在现有FE中添加新FE节点

```bash
# 在FE Leader中添加新FE
mysql -h192.168.1.10 -P9030 -uroot -e "ALTER SYSTEM ADD FOLLOWER 'new_server_ip:9010';"
```

## 注意事项

- Host 网络模式下容器直接使用宿主机网络，性能最优
- 确保防火墙正确配置，开放必要端口
- 定期备份FE元数据和MinIO数据
- 监控资源使用情况，及时调整配置
- 生产环境建议使用外部负载均衡器