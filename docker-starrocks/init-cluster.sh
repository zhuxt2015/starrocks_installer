#!/bin/bash

# StarRocks 存算分离集群初始化脚本

set -e

echo "=== StarRocks 存算分离集群初始化 ==="

# 等待 FE Leader 启动
echo "等待 FE Leader 启动..."
sleep 30

# 检查 FE Leader 是否就绪
while ! docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "SHOW FRONTENDS;" 2>/dev/null; do
    echo "等待 FE Leader 就绪..."
    sleep 10
done

echo "FE Leader 已就绪"

# 添加 FE Follower 节点
echo "添加 FE Follower 节点..."
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD FOLLOWER 'fe2:9010';" || true
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD FOLLOWER 'fe3:9010';" || true

# 等待 FE Follower 节点加入
sleep 20

# 添加 CN 节点
echo "添加 CN 节点..."
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD COMPUTE NODE 'cn1:9050';" || true
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD COMPUTE NODE 'cn2:9050';" || true
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD COMPUTE NODE 'cn3:9050';" || true

# 等待节点注册完成
sleep 30

# 检查集群状态
echo "=== 检查集群状态 ==="
echo "FE 节点状态:"
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "SHOW FRONTENDS;"

echo "CN 节点状态:"
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "SHOW COMPUTE NODES;"

# 创建 MinIO bucket
echo "=== 配置 MinIO ==="
docker exec minio mc alias set local http://localhost:9000 minioadmin minioadmin123
docker exec minio mc mb local/starrocks-data || true
docker exec minio mc policy set public local/starrocks-data

# 创建存储卷
echo "=== 创建存储卷 ==="
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "
CREATE STORAGE VOLUME starrocks_storage_volume
TYPE = S3
LOCATIONS = ('s3://starrocks-data/')
PROPERTIES (
    'aws.s3.region' = 'us-east-1',
    'aws.s3.endpoint' = 'http://172.20.0.10:9000',
    'aws.s3.use_aws_sdk_default_behavior' = 'false',
    'aws.s3.use_instance_profile' = 'false',
    'aws.s3.access_key' = 'minioadmin',
    'aws.s3.secret_key' = 'minioadmin123',
    'aws.s3.enable_ssl' = 'false',
    'aws.s3.enable_path_style_access' = 'true'
);" || true

# 设置默认存储卷
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "SET starrocks_storage_volume = 'starrocks_storage_volume';" || true

echo "=== 集群初始化完成 ==="
echo "FE Leader 访问地址: http://localhost:8030"
echo "FE2 访问地址: http://localhost:8031" 
echo "FE3 访问地址: http://localhost:8032"
echo "MinIO 控制台: http://localhost:9001 (minioadmin/minioadmin123)"
echo "MySQL 连接: mysql -h127.0.0.1 -P9030 -uroot"

echo "=== 最终集群状态检查 ==="
sleep 10
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "SHOW FRONTENDS;"
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "SHOW COMPUTE NODES;"
docker exec starrocks-fe1 mysql -h127.0.0.1 -P9030 -uroot -e "SHOW STORAGE VOLUMES;"