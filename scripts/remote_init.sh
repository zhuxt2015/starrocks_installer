#!/bin/bash
###################################################
# 功能: 集群配置初始化
###################################################
set -eu
#这些变量在执行前会被替换
repo_domain="mirrors.aliyun.com"
yum_repo_url="http://mirrors.aliyun.com/repo/Centos-7.repo"
ntp_server_ip="10.138.132.122"
jdk_package="java-1.8.0-openjdk-devel.x86_64"
java_home="/usr/lib/jvm/java-11-openjdk"

###################################################
# 设置字符集为en_US.UTF8
###################################################
function set_utf8()
{
    current_lang=$(echo $LANG)

    if [ "$current_lang" != "en_US.UTF-8" ]; then
        echo "Current LANG is $current_lang, not en_US.UTF-8, updating..."

        # 根据不同的 Linux 发行版,修改语言设置的方式可能不同
        # 以下是针对 CentOS/RHEL 7 的修改方式
        export LANG=en_US.UTF8
        sed -i 's/^LANG=.*/LANG="en_US.UTF-8"/' /etc/locale.conf

        echo "LANG has been updated to en_US.UTF-8"
        echo "Please restart your server for the changes to take effect."
    else
        echo "Current LANG is already en_US.UTF-8"
    fi
}


###################################################
# 修改系统限制参数（最大打开文件数以及最大进程数）
###################################################

function set_limits()
{
	if ! grep -q "^* soft nofile" /etc/security/limits.conf
	then
		echo "* soft nofile 655350" >>/etc/security/limits.conf
	fi

	if ! grep -q "^* hard nofile" /etc/security/limits.conf
	then
		echo "* hard nofile 655350" >>/etc/security/limits.conf
	fi
	if ! grep -q "^* hard nproc" /etc/security/limits.conf
	then
		echo "* hard nproc 65535" >>/etc/security/limits.conf
	fi
	if ! grep -q "^* soft nproc" /etc/security/limits.conf
	then
		echo "* soft nproc 65535" >>/etc/security/limits.conf
	fi
	if ! grep -q "^* soft stack" /etc/security/limits.conf
	then
		echo "* soft stack unlimited" >>/etc/security/limits.conf
	fi
	if ! grep -q "^* hard stack" /etc/security/limits.conf
	then
		echo "* hard stack unlimited" >>/etc/security/limits.conf
	fi
	if ! grep -q "^* soft memlock" /etc/security/limits.conf
	then
		echo "* soft memlock unlimited" >>/etc/security/limits.conf
	fi
	if ! grep -q "^* hard memlock" /etc/security/limits.conf
	then
		echo "* hard memlock unlimited" >>/etc/security/limits.conf
	fi

	sed -i "s/4096/65535/g" /etc/security/limits.d/20-nproc.conf
}

###################################################
# 关闭SELinux
###################################################

function off_selinux()
{
    sed -i "s/^SELINUX=.*/SELINUX=disabled/g" /etc/sysconfig/selinux
	  sed -i 's/SELINUXTYPE/#SELINUXTYPE/' /etc/selinux/config
    sed -i "s/^SELINUX=.*/SELINUX=disabled/g" /etc/selinux/config
    SELStatus=$(/usr/sbin/getenforce)
    if [ "X"${SELStatus} = "XPermissive" -o "X"${SELStatus} = "XDisabled" ] ;
    then
      echo 'succeed to close SELinux.'
    else
      setenforce 0
    fi
}


###################################################
# 禁用透明大页(THP)
###################################################

function off_THP()
{
    if test -f /sys/kernel/mm/transparent_hugepage/enabled;
    then
        echo never > /sys/kernel/mm/transparent_hugepage/enabled
        echo 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' >> /etc/rc.local

    fi
    if test -f /sys/kernel/mm/transparent_hugepage/defrag;
    then
        echo never > /sys/kernel/mm/transparent_hugepage/defrag
        echo 'echo never > /sys/kernel/mm/transparent_hugepage/defrag' >> /etc/rc.local

    fi
}

###################################################
# 禁用交换分区(root用户)
###################################################

function off_swappiness()
{
	/usr/sbin/swapoff -a
  /usr/sbin/sysctl vm.swappiness=0
	if ! grep -q "vm.swappiness=" /etc/sysctl.conf
	then
		  echo "vm.swappiness=0" >> /etc/sysctl.conf
	else
      sed -i "s/^vm.swappiness=.*/vm.swappiness=0/g" /etc/sysctl.conf
	fi
}

###################################################
# 网络参数
###################################################

function net_config()
{
  #如果系统当前因后台进程无法处理的新连接而溢出，则允许系统重置新连接
	if ! grep -q "net.ipv4.tcp_abort_on_overflow=1" /etc/sysctl.conf
	then
		echo "net.ipv4.tcp_abort_on_overflow=1" >> /etc/sysctl.conf
	fi
  #设置监听 Socket 队列的最大连接请求数为 1024
  if ! grep -q "net.core.somaxconn=1024" /etc/sysctl.conf
	then
		echo "net.core.somaxconn=1024" >> /etc/sysctl.conf
	fi
  #Memory Overcommit 允许操作系统将额外的内存资源分配给进程
  if ! grep -q "^vm.overcommit_memory" /etc/sysctl.conf
	then
		echo "vm.overcommit_memory=1" >> /etc/sysctl.conf
	fi

}

###################################################
# 设置umask
###################################################

function set_umask()
{
	if ! grep -q "^umask 022" /etc/profile
	then
    echo "umask 022" >> /etc/profile
	fi
}

###################################################
# 设置主机时间同步
###################################################

function set_ntpd()
{
    if ! rpm -q ntp &> /dev/null;then
        yum install ntp -y > /dev/null
    fi
    ip=`ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|grep 10.|head -1`
	sed -i 's/^server 0.centos.pool.ntp.org iburst/#server 0.centos.pool.ntp.org iburst/' /etc/ntp.conf
	sed -i 's/^server 1.centos.pool.ntp.org iburst/#server 1.centos.pool.ntp.org iburst/' /etc/ntp.conf
	sed -i 's/^server 2.centos.pool.ntp.org iburst/#server 2.centos.pool.ntp.org iburst/' /etc/ntp.conf
	sed -i 's/^server 3.centos.pool.ntp.org iburst/#server 3.centos.pool.ntp.org iburst/' /etc/ntp.conf
	if [ "$ip" != "${ntp_server_ip}" ]  && ! grep -q "server ${ntp_server_ip}" /etc/ntp.conf
	then
	    echo "server ${ntp_server_ip} prefer" >> /etc/ntp.conf
	elif [ "$ip" == "${ntp_server_ip}" ]
	then
	    if ! grep -q "^server 127.127.1.0" /etc/ntp.conf
	    then
	        echo "server 127.127.1.0 " >> /etc/ntp.conf
	    fi
	    if ! grep -q "^fudge 127.127.1.0 stratum 10" /etc/ntp.conf
	    then
	        echo "fudge 127.127.1.0 stratum 10 " >> /etc/ntp.conf
	    fi
	fi
	#关闭chronyd
    if command -v /usr/sbin/chronyd &> /dev/null;then
      echo "chrony already installed, disable chrony"
      systemctl stop chronyd
      systemctl disable chronyd
    fi
    systemctl enable ntpd
    systemctl start ntpd
    systemctl enable ntpd
}

###################################################
# 关闭防火墙
###################################################

function off_firewall()
{
    systemctl stop firewalld
    systemctl disable firewalld
    systemctl status firewalld | grep inactive
}

###################################################
# 安装jdk
###################################################

function install_jdk()
{
    #install jdk
    if [ ! -d "$java_home" ]; then
	      echo "java is not installed,start to install java"
	      yum install -y $jdk_package > /dev/null
	  fi

    #set environment
    if ! grep -q "^export JAVA_HOME=" /etc/profile
    then
        echo "export JAVA_HOME=$java_home" | sudo tee -a /etc/profile
        echo "export PATH=\$PATH:\$JAVA_HOME/bin" | sudo tee -a /etc/profile
    else
        sed -i "s#^export JAVA_HOME=.*#export JAVA_HOME=$java_home#g" /etc/profile
        sed -i "s#^export PATH=.*#export PATH=\$PATH:\$java_home/bin#g" /etc/profile
    fi

    #update environment
    #source /etc/profile
    java -version
    echo "jdk is installed !"
}

###################################################
# 安装yum源
###################################################
function update_yum_repo()
{
    if [ -n "$repo_domain" ];then
        if ! grep -q "$repo_domain" /etc/yum.repos.d/*.repo;then
            echo "backup yum repo"
            mkdir -p /etc/yum.repos.d/repo_bak
            mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/repo_bak
            wget -O /etc/yum.repos.d/CentOS-Base.repo ${yum_repo_url}
            # 清理 YUM 缓存并生成新缓存
            yum clean all
            echo "yum repo update succeed!"
        fi
    fi
}

###################################################
#
# 入口函数
#
###################################################
function main()
{

    #设置字符集
    echo "begin set utf8"
    set_utf8
    if [ $? -ne 0 ]; then
        return 1
    fi

    #安装yum源
    echo "begin update yum repo"
    update_yum_repo
    if [ $? -ne 0 ]; then
        return 1
    fi

    #修改系统限制参数
    echo "begin set limits"
    set_limits
    if [ $? -ne 0 ]; then
        return 1
    fi

    #关闭SELinux
    echo "begin off selinux"
    off_selinux
    if [ $? -ne 0 ]; then
        return 1
    fi

    #禁用透明大页
    echo "begin off THP"
    off_THP
    if [ $? -ne 0 ]; then
        return 1
    fi

    #禁用交换分区(root用户)
    echo "begin off swap"
    off_swappiness
    if [ $? -ne 0 ]; then
        return 1
    fi

    #修改网络配置
    echo "begin net config"
    net_config
    if [ $? -ne 0 ]; then
        return 1
    fi

    #设置umask
    echo "begin set umask"
    set_umask
    if [ $? -ne 0 ]; then
        return 1
    fi

    #关闭防火墙
    echo "begin off firewall"
    off_firewall
    if [ $? -ne 0 ]; then
        return 1
    fi

    #安装jdk
	echo "begin install jdk"
    install_jdk
    if [ $? -ne 0 ]; then
        return 1
    fi


    #设置主机时间同步
    echo "begin set ntpd"
    set_ntpd
    if [ $? -ne 0 ]; then
        return 1
    fi

    /usr/sbin/sysctl -p
}

main