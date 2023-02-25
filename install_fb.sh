#!/bin/bash

# INSTALL_PATH='/opt/filebrowser'
VERSION='latest'

if [ ! -n "$2" ]; then
  INSTALL_PATH='/opt/filebrowser'
else
  if [[ $2 == */ ]]; then
    INSTALL_PATH=${2%?}
  else
    INSTALL_PATH=$2
  fi
  if ! [[ $INSTALL_PATH == */filebrowser ]]; then
    INSTALL_PATH="$INSTALL_PATH/filebrowser"
  fi
fi

RED_COLOR='\e[1;31m'
GREEN_COLOR='\e[1;32m'
YELLOW_COLOR='\e[1;33m'
BLUE_COLOR='\e[1;34m'
PINK_COLOR='\e[1;35m'
SHAN='\e[1;33;5m'
RES='\e[0m'
clear

# Get platform
if command -v arch >/dev/null 2>&1; then
  platform=$(arch)
else
  platform=$(uname -m)
fi

ARCH="UNKNOWN"

if [ "$platform" = "x86_64" ]; then
  ARCH=amd64
elif [ "$platform" = "aarch64" ]; then
  ARCH=arm64
fi

if [ "$(id -u)" != "0" ]; then
  echo -e "\r\n${RED_COLOR}出错了，请使用 root 权限重试！${RES}\r\n" 1>&2
  exit 1
elif [ "$ARCH" == "UNKNOWN" ]; then
  echo -e "\r\n${RED_COLOR}出错了${RES}，一键安装目前仅支持 x86_64和arm64 平台。"
  exit 1
elif ! command -v systemctl >/dev/null 2>&1; then
  echo -e "\r\n${RED_COLOR}出错了${RES}，无法确定你当前的 Linux 发行版。"
  exit 1
else
  if command -v netstat >/dev/null 2>&1; then
    check_port=$(netstat -lnp | grep 6081 | awk '{print $7}' | awk -F/ '{print $1}')
  else
    echo -e "${GREEN_COLOR}端口检查 ...${RES}"
    if command -v yum >/dev/null 2>&1; then
      yum install net-tools -y >/dev/null 2>&1
      check_port=$(netstat -lnp | grep 6081 | awk '{print $7}' | awk -F/ '{print $1}')
    else
      apt-get update >/dev/null 2>&1
      apt-get install net-tools -y >/dev/null 2>&1
      check_port=$(netstat -lnp | grep 6081 | awk '{print $7}' | awk -F/ '{print $1}')
    fi
  fi
fi

CHECK() {
  if [ -f "$INSTALL_PATH/filebrowser" ]; then
    echo "此位置已经安装，请选择其他位置，或使用更新命令"
    exit 0
  fi
  if [ $check_port ]; then
    kill -9 $check_port
  fi
  if [ ! -d "$INSTALL_PATH/" ]; then
    mkdir -p $INSTALL_PATH
  else
    rm -rf $INSTALL_PATH && mkdir -p $INSTALL_PATH
  fi
}
#自动放行端口
function chk_firewall(){
	if [ -e "/etc/sysconfig/iptables" ]
	then
		iptables -I INPUT -p tcp --dport 6081 -j ACCEPT
		service iptables save
		service iptables restart
	elif [ -e "/etc/firewalld/zones/public.xml" ]
	then
		firewall-cmd --zone=public --add-port=6081/tcp --permanent
		firewall-cmd --reload
	elif [ -e "/etc/ufw/before.rules" ]
	then
		sudo ufw allow 6081/tcp
	fi
}
#关闭端口
function del_post() {
	if [ -e "/etc/sysconfig/iptables" ]
	then
		sed -i '/^.*6081.*/'d /etc/sysconfig/iptables
		service iptables save
		service iptables restart
	elif [ -e "/etc/firewalld/zones/public.xml" ]
	then
		firewall-cmd --zone=public --remove-port=6081/tcp --permanent
		firewall-cmd --reload
	elif [ -e "/etc/ufw/before.rules" ]
	then
		sudo ufw delete allow 6081/tcp
	fi
}
INSTALL() {
  # 下载 filebrowser 程序
  # 定义版本变量
  tag=$(wget -qO- -t1 -T2 "https://api.github.com/repos/filebrowser/filebrowser/releases/latest" | jq -r '.tag_name')
  echo -e "\r\n${GREEN_COLOR}下载 filebrowser $VERSION ...${RES}"
  echo -e "https://ghproxy.com/https://github.com/filebrowser/filebrowser/releases/download/${tag}/linux-$ARCH-filebrowser.tar.gz"
  curl -L https://ghproxy.com/https://github.com/filebrowser/filebrowser/releases/download/${tag}/linux-$ARCH-filebrowser.tar.gz -o /tmp/filebrowser.tar.gz $CURL_BAR
  tar zxf /tmp/filebrowser.tar.gz -C $INSTALL_PATH/

  if [ -f $INSTALL_PATH/filebrowser ]; then
    echo -e "${GREEN_COLOR} 下载成功 ${RES}"
  else
    echo -e "${RED_COLOR}下载 linux-filebrowser-$ARCH.tar.gz 失败！${RES}"
    exit 1
  fi

  # 删除下载缓存
  rm -f /tmp/filebrowser*
}

INIT() {
  if [ ! -f "$INSTALL_PATH/filebrowser" ]; then
    echo -e "\r\n${RED_COLOR}出错了${RES}，当前系统未安装 filebrowser\r\n"
    exit 1
  else
    rm -f $INSTALL_PATH/filebrowser.db
  fi

  #配置filebrowser
  #创建配置数据库
  $INSTALL_PATH/filebrowser -d $INSTALL_PATH/filebrowser.db config init
  #设置监听地址
  $INSTALL_PATH/filebrowser -d $INSTALL_PATH/filebrowser.db config set --address 0.0.0.0
  #设置监听端口
  $INSTALL_PATH/filebrowser -d $INSTALL_PATH/filebrowser.db config set --port 6081
  #设置中文语言环境
  $INSTALL_PATH/filebrowser -d $INSTALL_PATH/filebrowser.db config set --locale zh-cn
  #设置日志文件位置
  $INSTALL_PATH/filebrowser -d $INSTALL_PATH/filebrowser.db config set --log /var/log/filebrowser.log
  #设置根路径和aria2下载路径一致
  $INSTALL_PATH/filebrowser -d $INSTALL_PATH/filebrowser.db config set --root /root/Downloads
  #添加用户
  $INSTALL_PATH/filebrowser -d $INSTALL_PATH/filebrowser.db users add admin admin --perm.admin

  # 创建 systemd
  cat >/etc/systemd/system/filebrowser.service <<EOF
[Unit]
Description=filebrowser service
Wants=network.target
After=network.target network.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_PATH
ExecStart=$INSTALL_PATH/filebrowser -d $INSTALL_PATH/filebrowser.db
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

  # 添加开机启动
  systemctl daemon-reload
  systemctl enable filebrowser >/dev/null 2>&1

}

SUCCESS() {
  clear
  echo "filebrowser 安装成功！"
  echo -e "\r\n访问地址：${GREEN_COLOR}http://YOUR_IP:6081/${RES}\r\n"

  echo -e "---------管理员信息--------"
  echo -e "用户名：admin"
  echo -e "密码：admin"
  echo -e "--------------------------"

  echo -e "启动服务中"
  systemctl restart filebrowser

  echo
  echo -e "查看状态：${GREEN_COLOR}systemctl status filebrowser${RES}"
  echo -e "启动服务：${GREEN_COLOR}systemctl start filebrowser${RES}"
  echo -e "重启服务：${GREEN_COLOR}systemctl restart filebrowser${RES}"
  echo -e "停止服务：${GREEN_COLOR}systemctl stop filebrowser${RES}"
  echo -e "\r\n温馨提示：如果端口无法正常访问，请检查 \033[36m服务器安全组、本机防火墙、filebrowser状态\033[0m"
  echo
}

UNINSTALL() {
  echo -e "\r\n${GREEN_COLOR}卸载 filebrowser ...${RES}\r\n"
  echo -e "${GREEN_COLOR}停止进程${RES}"
  systemctl disable filebrowser >/dev/null 2>&1
  systemctl stop filebrowser >/dev/null 2>&1
  echo -e "${GREEN_COLOR}清除残留文件${RES}"
  rm -rf $INSTALL_PATH /etc/systemd/system/filebrowser.service
  rm -f /var/log/filebrowser.log
  systemctl daemon-reload
  echo -e "\r\n${GREEN_COLOR}filebrowser 已在系统中移除！${RES}\r\n"
}

UPDATE() {
  if [ ! -f "$INSTALL_PATH/filebrowser" ]; then
    echo -e "\r\n${RED_COLOR}出错了${RES}，当前系统未安装 filebrowser\r\n"
    exit 1
  else
    echo
    echo -e "${GREEN_COLOR}停止 filebrowser 进程${RES}\r\n"
    systemctl stop filebrowser
    # 备份 filebrowser 二进制文件，供下载更新失败回退
    cp $INSTALL_PATH/filebrowser /tmp/filebrowser.bak
    # 定义版本变量
    tag=$(wget -qO- -t1 -T2 "https://api.github.com/repos/filebrowser/filebrowser/releases/latest" | jq -r '.tag_name')
    echo -e "${GREEN_COLOR}下载 filebrowser $VERSION ...${RES}"
    echo -e "https://ghproxy.com/https://github.com/filebrowser/filebrowser/releases/download/${tag}/linux-$ARCH-filebrowser.tar.gz"
    curl -L https://ghproxy.com/https://github.com/filebrowser/filebrowser/releases/download/${tag}/linux-$ARCH-filebrowser.tar.gz -o /tmp/filebrowser.tar.gz $CURL_BAR
    tar zxf /tmp/filebrowser.tar.gz -C $INSTALL_PATH/
    if [ -f $INSTALL_PATH/filebrowser ]; then
      echo -e "${GREEN_COLOR} 下载成功 ${RES}"
    else
      echo -e "${RED_COLOR}下载 linux-filebrowser-$ARCH.tar.gz 出错，更新失败！${RES}"
      echo "回退所有更改 ..."
      mv /tmp/filebrowser.bak $INSTALL_PATH/filebrowser
      systemctl start filebrowser
      exit 1
    fi
    echo -e "---------管理员信息--------"
    echo -e "用户名：admin"
    echo -e "密码：admin"
    echo -e "--------------------------"
    echo -e "\r\n${GREEN_COLOR}启动 filebrowser 进程${RES}"
    systemctl start filebrowser
    echo -e "\r\n${GREEN_COLOR}filebrowser 已更新到最新稳定版！${RES}\r\n"
    # 删除临时文件
    rm -f /tmp/filebrowser*
  fi
}

# CURL 进度显示
if curl --help | grep progress-bar >/dev/null 2>&1; then # $CURL_BAR
  CURL_BAR="--progress-bar"
fi

# The temp directory must exist
if [ ! -d "/tmp" ]; then
  mkdir -p /tmp
fi

# Fuck bt.cn (BT will use chattr to lock the php isolation config)
chattr -i -R $INSTALL_PATH >/dev/null 2>&1

if [ "$1" = "uninstall" ]; then
  del_post
  UNINSTALL
elif [ "$1" = "update" ]; then
  UPDATE
elif [ "$1" = "install" ]; then
  CHECK
  chk_firewall
  INSTALL
  INIT
  if [ -f "$INSTALL_PATH/filebrowser" ]; then
    SUCCESS
  else
    echo -e "${RED_COLOR} 安装失败${RES}"
  fi
else
  echo -e "${RED_COLOR} 错误的命令${RES}"
fi