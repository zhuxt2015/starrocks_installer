#!/bin/bash

#忽略的磁盘
ignore_disk=$(lsblk -nlo NAME,MOUNTPOINT | awk '$2=="/boot" {print $1}' | sed 's/[0-9]*$//')

# 计数器,用于创建挂载点
counter=1
prefix=/data

devices=$(lsblk -d -o NAME,TYPE | grep 'disk' | awk '{print $1}' | grep -v $ignore_disk)

# 遍历所有磁盘设备
for device in $devices
do
  disk=/dev/$device

  echo $disk
  # 检查设备是否已经挂载
  is_mounted=$(grep $disk /etc/mtab)
  if [ "$is_mounted" ];then
    continue
  fi

  # 使用parted命令格式化磁盘为GPT类型
  parted -s ${disk} mklabel gpt

  # 创建primary分区
  parted -s ${disk} mkpart primary 0% 100% > /dev/null

  # 获取分区名
  partition=$(ls ${disk}* | grep -v "^${disk}$")

  # 格式化分区为ext4
  mkfs.ext4 ${partition}

  # 创建挂载点
  mkdir -p $prefix$(printf "%01d" ${counter})

  # 挂载分区到挂载点
  mount ${partition} $prefix$(printf "%01d" ${counter})

  # 获取分区UUID
  uuid=$(blkid -s UUID -o value ${partition})

  # 构造fstab内容
  fstab_content="UUID=${uuid} $prefix$(printf "%01d" ${counter}) ext4 defaults 0 0"

  # 追加一条挂载信息到fstab
  echo ${fstab_content} >> /etc/fstab

  # 计数器递增
  counter=$((counter+1))
done
df -h