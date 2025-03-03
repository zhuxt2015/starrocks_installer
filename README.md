# StarRocks一键安装指南
> 💡 提示：本工具特别适合以下场景:
> - 快速搭建测试/开发环境
> - 评估新版本特性
> - 临时部署验证概念
> - 学习和熟悉StarRocks

![demo.gif](https://zhuxt2015.github.io/picx-images-hosting/demo.7i0izckke1.gif)

StarRocks 是一款高性能分析型数据仓库，使用向量化、MPP 架构、CBO、智能物化视图、可实时更新的列式存储引擎等技术实现多维、实时、高并发的数据分析。StarRocks 既支持从各类实时和离线的数据源高效导入数据，也支持直接分析数据湖上各种格式的数据。StarRocks 兼容 MySQL 协议，可使用 MySQL 客户端和常用 BI 工具对接。同时 StarRocks 具备水平扩展，高可用、高可靠、易运维等特性。广泛应用于实时数仓、OLAP 报表、数据湖分析等场景。


[![Apache License 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)


## 目录
- [支持版本](#支持版本)
- [支持部署模式](#支持部署模式)
- [兼容系统](#兼容系统)
- [项目初衷](#项目初衷)
- [功能特性](#-功能特性)
- [快速部署](#快速部署)
- [配置说明](#配置说明)
- [常见问题](#常见问题)
- [获取帮助](#获取帮助)
- [贡献](#贡献)


## 支持版本
| 版本    | 状态    |
|-------|-------|
| 3.x.x | ✅ 已测试 |
| 2.x.x | 待测试   |

## 支持部署模式
| 部署模式     | 状态    |
|----------|-------|
| 单节点 存算一体 | ✅ 已测试 |
| 集群 存算一体  | ✅ 已测试 |
| 单节点 存算分离 | 待支持   |
| 集群 存算分离  | 待支持   |

## 兼容系统
| 操作系统 | 版本              | 状态   |
|----------|-----------------|------|
| CentOS | 7.9             | ✅ 已验证 |
| Ubuntu | 20.04+          |待支持 |





## 项目初衷


这个一键安装工具的设计初衷是:

1.  **降低使用门槛**
    - 面向小白用户,提供最简单的部署方式
    - 自动处理环境初始化和配置,避免繁琐的手动设置
    - 提供清晰的中文提示和引导

2.  **快速体验新版本**
    - 让开发者能快速部署和体验最新版StarRocks
    - 便于评估是否需要升级现有环境

3.  **简化集群部署**
    - 自动化处理集群配置和节点分发
    - 自动创建目录
    - 提供完整的部署检查和验证
    - 自动配置开机自启


## ✨ 功能特性

1. 系统检查
    - [x] 检查服务器支持AVX2
    - [x] 检查节点内存和cpu
    - [x] 检查端口占用
2. 安装用户创建
3. ssh免密认证
4. 系统环境初始化
    - [x] 设置字符集
    - [x] 安装yum源
    - [x] 修改系统限制参数
    - [x] 关闭SELinux
    - [x] 禁用透明大页
    - [x] 禁用交换分区
    - [x] 修改网络配置
    - [x] 设置umask
    - [x] 关闭防火墙
    - [x] 设置时钟同步
5. JDK安装
6. 在线安装、离线安装
7. 初始化FE root密码
8. systemd开机自启动，宕机自重启
9. 批量滚动重启
10. 配置同步分发
11. 分发auditloader.zip、hadoop配置文件、hive配置文件、JDBC驱动文件
12. 增删节点
13. 滚动升级
14. 滚动降级
15. 删除集群


## 快速部署

> ⚠️ 注意：
> - 安装用户必须具有sudo权限或者是root用户
> - 安装脚本部署的机器默认为FE leader节点
> - 如未安装Java会提示自动安装:
> - 由于StarRocks安装包较大，建议提前下载到本地，缩短安装耗时

```bash
# 第一步：下载并解压

# 第二步：进入目录并执行安装
cd starrocks_installer 
chmod +x install_starrocks.sh

# 第三部: 修改config.properties中的配置(可选)
config/config.properties
config/hosts.properties
config/fe.conf
config/be.conf

# 第四步：执行安装
./install_starrocks.sh

```

### 升级集群
> - 滚动升级各个节点，建议先升级一个BE观察一下，再决定整体升级(将config.properties中的backend配置一个BE的IP)
> - 先升级 BE，然后升级 FE，先升级follower FE,再升级leader FE
> - 升级过程中，FE leader节点会自动切换为FE follower节点
```bash
#第一步 修改升级版本号
vim config.properties
upgrade_version=3.3.10
# 第二步 执行升级
./upgrade/upgrade_cluster.sh
```

### 降级集群
> - 滚动降级各个节点，建议先降级一个follower FE观察一下，再决定整体升级(修改downgrade/downgrade_cluster.sh，for循环中最后一行增加return 0)
> - 先降级FE，然后降级BE, 先降级follower FE,再降级leader FE
> - 降级过程中，FE leader节点会自动切换为FE follower节点
```bash
#第一步 修改降级版本号
vim config.properties
downgrade_version=3.3.5
# 第二步 执行降级
./downgrade/downgrade_cluster.sh
```


### 卸载StarRocks
> ⚠️ 注意：卸载操作将
> - 停止所有 StarRocks 服务
> - 删除存储路径、日志路径、安装路径（如果已配置）
> - 删除安装用户

```bash
# 执行卸载
./uninstall.sh
```

## 操作命令
### 集群管理
| 操作 | 命令                                 
|------|------------------------------------|
| 启动集群 | `./start_cluster.sh`               |
| 停止集群 | `./stop_cluster.sh`                |
| 升级集群 | `./upgrade/upgrade_cluster.sh`        |
| 降级集群 | `./downgrade/downgrade_cluster.sh` |
| 配置分发 | `./scripts/config_distribution.sh` |


### 服务管理
| 操作 | 命令                                               |
|------|--------------------------------------------------|
| 启动服务 | `sudo systemctl start starrocks_fe/starrocks_be` |
| 停止服务 | `sudo systemctl stop starrocks_fe/starrocks_be`           |
| 重启服务 | `sudo systemctl restart starrocks_fe/starrocks_be`        |
| 查看状态 | `sudo systemctl status starrocks_fe/starrocks_be`         |
| 启用自启动 | `sudo systemctl enable starrocks_fe/starrocks_be`         |
| 禁用自启动 | `sudo systemctl disable starrocks_fe/starrocks_be`        |





## 配置说明

### config.properties安装配置
```properties
####################################必选配置####################################
#联网安装
online_install=true
#安装用户
install_user=test_sr
#fe leader node
leader=10.138.132.122
#fe follower node
follower=10.138.132.106,10.138.132.124
#be node
backend=10.138.132.106,10.138.132.124,10.138.132.126
#yum 仓库域名
repo_domain=mirrors.aliyun.com
#yum repo文件下载地址
yum_repo_url=http://mirrors.aliyun.com/repo/Centos-7.repo
#starrocks安装包下载地址
starrocks_download_url=https://releases.mirrorship.cn/starrocks/
#starrocks版本
starrocks_version=3.3.5
#安装包存放路径
package_path=/tmp/
#starrocks安装路径
install_path=/opt/test_sr/
#fe配置文件路径
fe_conf_path=/opt/test_sr/fe/conf/fe.conf
#be配置文件路径
be_conf_path=/opt/test_sr/be/conf/be.conf
#be存储路径
storage_root_path=/data/storage,medium:HDD
#yum安装jdk包名
jdk_package=java-11-openjdk-devel.x86_64
#java home路径
java_home=/usr/lib/jvm/java-11-openjdk
####################################非必选配置####################################
#hdfs配置文件路径
hdfs_site_file=/home/starrocks/hdfs-site.xml
#core site文件路径
core_site_file=/home/starrocks/core-site.xml
#fe root密码
fe_root_password=
#starrocks升级包文件路径
upgrade_version=3.3.10
#starrocks升级包文件路径
downgrade_version=3.3.5
```

### hosts.properties主机配置
```properties
# 使用普通用户+ sudo
host=10.138.132.122
port=22
user=vmuser
password=yili123!
root_password=root_password
use_sudo=true

# 使用root用户
host=10.138.132.126
port=22
user=vmuser
password=yili123!
root_password=root_password
use_sudo=true

# 同时配置sudo和root（优先使用sudo）
host=10.138.132.124
port=22
user=vmuser
password=yili123!
root_password=root_password
use_sudo=true

host=10.138.132.106
port=22
user=vmuser
password=yili123!
root_password=root_password
use_sudo=true
```
### fe.conf配置
```properties
# IP 选择策略
priority_networks=10.138.132.0/24
#FE HTTP Server 端口
http_port = 8030
#FE Thrift Server 端口
rpc_port = 9020
#FE MySQL Server 端口
query_port = 9030
#FE 内部通讯端口
edit_log_port = 9010
LOG_DIR = /data/log/fe
sys_log_dir = /data/log/fe
audit_log_dir = /data/log/fe
meta_dir = /opt/test_sr/meta
```
### be.conf配置
```properties
# IP 选择策略
priority_networks=10.138.132.0/24
#BE Thrift Server 端口
be_port = 9060
#BE HTTP Server 端口
be_http_port = 8040
#BE 心跳服务端口
heartbeat_service_port = 9050
#BE bRPC 端口
brpc_port = 8060
storage_root_path = /data/storage,medium:HDD
sys_log_dir = /data/log/be
spill_local_storage_dir = /data/spill
```

## 常见问题

<details>
<summary>1. 安装失败如何处理？</summary>

- 检查安装日志
- 确认环境要求
- 验证网络连接
- 检查用户权限
</details>

<details>
<summary>2. 服务启动失败？</summary>

- 检查端口占用
- 验证配置文件
- 确认权限正确
- 查看服务日志
</details>

## 获取帮助

- [官方文档](https://docs.starrocks.io/zh/docs/introduction/StarRocks_intro/)
- [问题反馈](https://github.com/StarRocks/starrocks/issues)
- [中文社区](https://forum.mirrorship.cn/)

## 贡献

欢迎提交Issue和Pull Request来帮助改进这个安装器！