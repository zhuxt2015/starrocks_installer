#!/bin/bash

#忽略挂载了 /boot 或 /boot/efi 等系统分区的磁盘
ignore_disk=$(lsblk -nlo NAME,MOUNTPOINT | awk '$2 ~ /^\/boot(\/|$)/ {print $1}' | sed 's/[0-9]*$//' | head -n1)

# 计数器,用于创建挂载点
counter=1
prefix=/data

devices=$(lsblk -d -o NAME,TYPE | awk '$2=="disk" {print $1}')

if [ -n "$ignore_disk" ]; then
  devices=$(printf '%s\n' "$devices" | grep -Fvx "$ignore_disk" || true)
fi

if [ -z "$devices" ]; then
  echo "No available data disks found, skip disk mount."
  exit 0
fi

# 遍历所有磁盘设备
for device in $devices
do
  disk=/dev/$device

  echo "Processing disk: $disk"
  # 检查设备是否已经挂载
  is_mounted=$(grep -F "$disk" /etc/mtab || true)
  if [ "$is_mounted" ];then
    echo "Skip mounted disk: $disk"
    continue
  fi

  # 使用parted命令格式化磁盘为GPT类型
  parted -s ${disk} mklabel gpt

  # 创建primary分区
  parted -s ${disk} mkpart primary 0% 100% > /dev/null

  partprobe ${disk}
  udevadm settle

  # 获取分区名,普通磁盘是 /dev/vdb1,nvme 磁盘是 /dev/nvme0n1p1
  partition=$(lsblk -nrpo NAME,TYPE ${disk} | awk '$2 == "part" { print $1; exit }')
  if [ -z "${partition}" ] || [ ! -b "${partition}" ]; then
    echo "Failed to find partition for ${disk} after partition creation."
    exit 1
  fi

  # 格式化分区为ext4
  mkfs.ext4 -F ${partition}

  mount_dir=$prefix$(printf "%01d" ${counter})

  # 创建挂载点
  mkdir -p ${mount_dir}

  # 挂载分区到挂载点
  mount ${partition} ${mount_dir}

  # 获取分区UUID
  uuid=$(blkid -s UUID -o value ${partition})

  # 构造fstab内容
  fstab_content="UUID=${uuid} ${mount_dir} ext4 defaults 0 0"

  # 如果fstab已存在相同挂载目录,更新UUID;否则追加一条挂载信息
  if awk -v mount_dir="${mount_dir}" '$2 == mount_dir { found=1 } END { exit found ? 0 : 1 }' /etc/fstab; then
    awk -v mount_dir="${mount_dir}" -v fstab_content="${fstab_content}" '
      $2 == mount_dir { print fstab_content; next }
      { print }
    ' /etc/fstab > /tmp/fstab.tmp
    cat /tmp/fstab.tmp > /etc/fstab
    rm -f /tmp/fstab.tmp
  else
    echo ${fstab_content} >> /etc/fstab
  fi
  systemctl daemon-reload

  # 计数器递增
  counter=$((counter+1))
done
df -h
