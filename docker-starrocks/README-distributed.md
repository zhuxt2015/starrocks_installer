# StarRocks 3.3.17 分布式存算分离部署

> 🚀 基于 3台服务器的 StarRocks 存算分离架构分布式部署方案

## 架构设计

### 服务器分布
| 服务器 | 组件 | IP地址 | 端口 |
|--------|------|--------|------|
| Server1 | FE1(Leader) + CN1 + MinIO | 192.168.1.10 | FE:8030,9030,9020,9010 CN:8040,9060,8060,9050 MinIO:9000,9001 |
| Server2 | FE2(Follower) + CN2 | 192.168.1.11 | FE:8030,9030,9020,9010 CN:8040,9060,8060,9050 |
| Server3 | FE3(Follower) + CN3 | 192.168.1.12 | FE:8030,9030,9020,9010 CN:8040,9060,8060,9050 |

### 网络架构
- **容器内网络**: 每台服务器使用 172.20.0.0/16 子网
- **跨服务器通信**: 通过 extra_hosts 配置实现服务发现
- **对象存储**: MinIO 部署在 Server1，其他节点通过网络访问

## 系统要求

- **操作系统**: Ubuntu 22.04 LTS
- **硬件配置**: 每台服务器 32GB内存 + 8核CPU + 100GB磁盘
- **网络**: 服务器间网络互通，建议千兆网络
- **软件**: Docker 20.10+ 和 Docker Compose 2.0+

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

### 2. 一键部署

```bash
# 完整部署 (检查SSH + 安装Docker + 部署配置 + 启动服务 + 初始化集群)
./deploy.sh

# 分步部署
./deploy.sh --check-only    # 仅检查SSH连接
./deploy.sh --install-only  # 仅安装Docker
./deploy.sh --deploy-only   # 仅部署配置
./deploy.sh --start-only    # 仅启动服务
./deploy.sh --init-only     # 仅初始化集群
```

### 3. 验证部署

```bash
# 连接到集群
mysql -h192.168.1.10 -P9030 -uroot

# 检查集群状态
SHOW FRONTENDS;
SHOW COMPUTE NODES;
SHOW STORAGE VOLUMES;
```

## 手动部署步骤

如果自动部署脚本无法使用，可以按以下步骤手动部署：

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

## 配置说明

### 网络配置
- 每台服务器使用独立的 Docker Compose 文件
- 通过 `extra_hosts` 实现跨服务器的服务发现
- 容器内使用固定IP，便于配置管理

### 存储配置
- MinIO 部署在 Server1，提供 S3 兼容的对象存储
- 所有CN节点通过网络访问 MinIO 进行数据读写
- 本地缓存配置：Block Cache 6GB + Data Cache 2GB

### 高可用配置
- 3个FE节点提供元数据服务高可用
- 1个Leader + 2个Follower，支持自动故障切换
- CN节点无状态，支持动态扩缩容

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

### 数据备份

```bash
# 备份FE元数据 (在Server1执行)
docker exec starrocks-fe1 tar -czf /tmp/fe_meta_backup.tar.gz /opt/starrocks/fe/meta
docker cp starrocks-fe1:/tmp/fe_meta_backup.tar.gz ./fe_meta_backup_$(date +%Y%m%d).tar.gz

# 备份MinIO数据
docker exec minio tar -czf /tmp/minio_backup.tar.gz /data
docker cp minio:/tmp/minio_backup.tar.gz ./minio_backup_$(date +%Y%m%d).tar.gz
```

## 故障排除

### 常见问题

1. **FE节点无法加入集群**
   - 检查网络连通性: `ping 192.168.1.10`
   - 检查端口是否开放: `telnet 192.168.1.10 9010`
   - 查看FE日志: `docker-compose logs fe1`

2. **CN节点连接失败**
   - 确认FE服务正常运行
   - 检查CN配置文件中的FE地址
   - 查看CN日志: `docker-compose logs cn1`

3. **MinIO连接问题**
   - 检查MinIO服务状态: `docker-compose ps minio`
   - 验证网络访问: `curl http://192.168.1.10:9000`
   - 检查防火墙设置

### 性能优化

1. **内存优化**
   - FE: 8GB JVM堆内存，适合32GB服务器
   - CN: 24GB内存限制，85%内存使用率
   - 缓存: 6GB Block Cache + 2GB Data Cache

2. **网络优化**
   - 使用千兆网络连接
   - 调整TCP缓冲区大小
   - 启用网络压缩

3. **存储优化**
   - 配置SSD本地缓存
   - 调整对象存储连接参数
   - 优化MinIO性能设置

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

- 首次部署需要等待镜像下载，建议提前拉取
- 确保服务器间网络互通，防火墙开放相应端口
- 生产环境建议使用外部负载均衡器
- 定期备份FE元数据和MinIO数据
- 监控资源使用情况，及时调整配置