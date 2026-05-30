# StarRocks 3.3.17 存算分离 Docker Compose 部署

> 🚀 基于 Docker Compose 的 StarRocks 存算分离架构部署方案，包含 3FE + 3CN + MinIO 对象存储

## 架构说明

- **3个 FE 节点**: 1个 Leader + 2个 Follower，提供高可用的元数据服务
- **3个 CN 节点**: 计算节点，负责查询执行，支持弹性扩缩容
- **MinIO**: S3 兼容的对象存储，用于数据持久化存储
- **存算分离**: 计算和存储完全分离，支持独立扩展

## 系统要求

- **服务器**: 3台 Ubuntu 22.04
- **内存**: 32GB 每台
- **磁盘**: 100GB 每台  
- **CPU**: 8核 每台
- **Docker**: 20.10+ 
- **Docker Compose**: 2.0+

## 网络规划

| 服务 | 容器名 | IP地址 | 端口映射 |
|------|--------|--------|----------|
| MinIO | minio | 172.20.0.10 | 9000:9000, 9001:9001 |
| FE1 (Leader) | starrocks-fe1 | 172.20.0.11 | 8030:8030, 9020:9020, 9030:9030, 9010:9010 |
| FE2 (Follower) | starrocks-fe2 | 172.20.0.12 | 8031:8030, 9021:9020, 9031:9030, 9011:9010 |
| FE3 (Follower) | starrocks-fe3 | 172.20.0.13 | 8032:8030, 9022:9020, 9032:9030, 9012:9010 |
| CN1 | starrocks-cn1 | 172.20.0.21 | 8040:8040, 9060:9060, 8060:8060 |
| CN2 | starrocks-cn2 | 172.20.0.22 | 8041:8040, 9061:9060, 8061:8060 |
| CN3 | starrocks-cn3 | 172.20.0.23 | 8042:8040, 9062:9060, 8062:8060 |

## 快速部署

### 1. 启动集群

```bash
# 启动所有服务
docker-compose up -d

# 查看服务状态
docker-compose ps
```

### 2. 初始化集群

```bash
# 执行集群初始化脚本
./init-cluster.sh
```

### 3. 验证部署

```bash
# 连接到 StarRocks
mysql -h127.0.0.1 -P9030 -uroot

# 查看集群状态
SHOW FRONTENDS;
SHOW COMPUTE NODES;
SHOW STORAGE VOLUMES;
```

## 配置优化说明

### FE 配置优化 (fe.conf)

- **内存配置**: JVM 堆内存设置为 8GB，适合 32GB 内存环境
- **存算分离**: 启用 `enable_shared_data = true`
- **MinIO 集成**: 配置 S3 兼容的对象存储连接
- **性能优化**: 启用 Pipeline 引擎和并行执行
- **高可用**: 配置集群容错和负载均衡

### CN 配置优化 (cn.conf)

- **内存限制**: 设置为系统内存的 85%，约 24GB
- **缓存配置**: 
  - Block Cache: 6GB 内存 + 20GB 磁盘
  - Data Cache: 2GB 内存 + 20GB 磁盘
- **并发优化**: 16个扫描线程，支持高并发查询
- **Spill 配置**: 自动溢写，内存阈值 80%
- **对象存储**: 直连 MinIO 进行数据读写

### MinIO 配置

- **访问凭证**: minioadmin/minioadmin123
- **存储桶**: starrocks-data (自动创建)
- **访问策略**: 公共读写权限
- **数据持久化**: 本地磁盘存储

## 管理命令

### 集群管理

```bash
# 启动集群
docker-compose up -d

# 停止集群  
docker-compose down

# 重启集群
docker-compose restart

# 查看日志
docker-compose logs -f [service_name]

# 扩容 CN 节点
docker-compose up -d --scale cn=5
```

### 服务访问

```bash
# StarRocks Web UI
http://localhost:8030    # FE1
http://localhost:8031    # FE2  
http://localhost:8032    # FE3

# MinIO 控制台
http://localhost:9001    # 用户名: minioadmin, 密码: minioadmin123

# MySQL 连接
mysql -h127.0.0.1 -P9030 -uroot
```

### 数据操作示例

```sql
-- 创建数据库
CREATE DATABASE test_db;
USE test_db;

-- 创建表 (存算分离模式)
CREATE TABLE test_table (
    id BIGINT,
    name VARCHAR(100),
    create_time DATETIME
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES (
    "replication_num" = "3",
    "storage_volume" = "starrocks_storage_volume"
);

-- 插入测试数据
INSERT INTO test_table VALUES 
(1, 'test1', '2024-01-01 10:00:00'),
(2, 'test2', '2024-01-01 11:00:00');

-- 查询数据
SELECT * FROM test_table;
```

## 监控和运维

### 健康检查

```bash
# 检查容器状态
docker-compose ps

# 检查 FE 状态
curl http://localhost:8030/api/health

# 检查 CN 状态  
curl http://localhost:8040/api/health

# 检查 MinIO 状态
curl http://localhost:9000/minio/health/live
```

### 日志查看

```bash
# FE 日志
docker-compose logs -f fe1

# CN 日志
docker-compose logs -f cn1

# MinIO 日志
docker-compose logs -f minio
```

### 数据备份

```bash
# 备份元数据 (FE)
docker exec starrocks-fe1 tar -czf /tmp/meta_backup.tar.gz /opt/starrocks/fe/meta

# 导出备份文件
docker cp starrocks-fe1:/tmp/meta_backup.tar.gz ./meta_backup.tar.gz
```

## 故障排除

### 常见问题

1. **FE 启动失败**
   - 检查端口占用: `netstat -tlnp | grep 8030`
   - 查看 FE 日志: `docker-compose logs fe1`
   - 检查内存是否充足

2. **CN 无法连接 FE**
   - 确认网络连通性: `docker exec cn1 ping fe1`
   - 检查 FE 是否正常运行
   - 验证配置文件中的 FE 地址

3. **MinIO 连接失败**
   - 检查 MinIO 服务状态: `docker-compose ps minio`
   - 验证访问凭证配置
   - 确认网络策略和防火墙设置

### 性能调优

1. **内存不足**
   - 调整 JVM 堆内存大小
   - 优化缓存配置
   - 启用内存自适应管理

2. **查询性能慢**
   - 增加 CN 节点数量
   - 调整并发线程数
   - 优化表结构和分区策略

3. **存储性能**
   - 配置 SSD 缓存
   - 调整 Block Cache 大小
   - 优化对象存储连接参数

## 注意事项

- 首次启动需要等待镜像下载，建议提前拉取镜像
- 存算分离模式下，所有数据存储在 MinIO 中，CN 节点无状态
- 生产环境建议使用外部对象存储服务 (如 AWS S3)
- 定期备份 FE 元数据，确保集群可恢复性
- 监控资源使用情况，及时调整配置参数