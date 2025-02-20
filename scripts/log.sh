#!/bin/bash

# 颜色输出函数
log_info() {
    date_time=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "\033[32m$date_time - [INFO] $1\033[0m"
}
log_warn() {
    date_time=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "\033[33m$date_time - [WARN] $1\033[0m"
}
log_error() {
    date_time=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "\033[31m$date_time - [ERROR] $1\033[0m"
}
