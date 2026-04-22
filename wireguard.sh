#!/bin/bash
clear

# WireGuard 一键管理脚本【功能完整版】
# 支持：Ubuntu/Debian
echo "====================================================="
echo "          WireGuard 一键管理脚本【增强版】"
echo "====================================================="
echo " 1. 全新安装 WireGuard（随机端口 + 自动配置）"
echo " 2. 添加新客户端用户（保留原有用户）"
echo " 3. 查看所有已添加的客户端用户"
echo " 4. 重启 WireGuard 服务"
echo " 5. 停止 WireGuard 服务"
echo " 6. 彻底卸载 WireGuard（清空所有配置）"
echo "====================================================="
read -p " 请输入操作序号 [1-6]：" ACTION

# ======================
# 选项 1：全新安装
# ======================
if [ "$ACTION" -eq 1 ]; then
    clear
    echo "正在彻底清理旧环境并安装..."

    # 彻底清理旧环境
    systemctl stop wg-quick@wg0 >/dev/null 2>&1
    apt remove --purge -y wireguard wireguard-dkms wireguard-tools >/dev/null 2>&1
    rm -rf /etc/wireguard >/dev/null 2>&1

    # 安装依赖
    apt update -y
    apt install -y software-properties-common
    add-apt-repository ppa:wireguard/wireguard -y
    apt update -y
    apt install -y linux-headers-$(uname -r) wireguard-dkms wireguard-tools qrencode iptables-persistent -y

    # 生成密钥
    SERVER_PRIVATE=$(wg genkey)
    SERVER_PUBLIC=$(echo $SERVER_PRIVATE | wg pubkey)
    CLIENT_PRIVATE=$(wg genkey)
    CLIENT_PUBLIC=$(echo $CLIENT_PRIVATE | wg pubkey)

    # 获取网卡与公网IP
    ETH=$(ip -o -4 route show to default | awk '{print $5}')
    IP=$(curl -s icanhazip.com)

    # 随机端口
    PORT=$(shuf -i 10000-60000 -n 1)

    # 写入服务端配置
    cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.0.0.1/24
PrivateKey = $SERVER_PRIVATE
ListenPort = $PORT
MTU = 1420

[Peer]
PublicKey = $CLIENT_PUBLIC
AllowedIPs = 10.0.0.2/32
EOF

    # 流量转发
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1

    # 防火墙
    iptables -t nat -F
    iptables -t nat -A POSTROUTING -o $ETH -j MASQUERADE
    iptables -I INPUT -p udp --dport $PORT -j ACCEPT
    iptables-save > /etc/iptables/rules.v4

    # 启动
    systemctl enable wg-quick@wg0
    systemctl restart wg-quick@wg0

    # 生成客户端配置
    cat > /etc/wireguard/android.conf << EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE
Address = 10.0.0.2/24
DNS = 8.8.8.8
MTU = 1420

[Peer]
PublicKey = $SERVER_PUBLIC
Endpoint = $IP:$PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    # 输出结果
    clear
    echo "============================================="
    echo " WireGuard 安装成功！【随机端口版】"
    echo "============================================="
    echo " 服务器端口：$PORT"
    echo " 公网IP：$IP"
    echo " 网卡：$ETH"
    echo "============================================="
    echo " 安卓配置（直接复制）："
    echo "============================================="
    cat /etc/wireguard/android.conf
    echo "============================================="
    echo " 安卓扫码连接："
    qrencode -t ansiutf8 < /etc/wireguard/android.conf
    exit 0

# ======================
# 选项 2：添加新用户
# ======================
elif [ "$ACTION" -eq 2 ]; then
    clear

    # 检查是否已安装
    if [ ! -f /etc/wireguard/wg0.conf ]; then
        echo "错误：未检测到 WireGuard 配置，请先执行 1 安装！"
        exit 1
    fi

    echo "正在添加新客户端..."
    NEW_PRIVATE=$(wg genkey)
    NEW_PUBLIC=$(echo "$NEW_PRIVATE" | wg pubkey)
    LAST_IP=$(grep -oP 'AllowedIPs = 10\.0\.0\.\K\d+' /etc/wireguard/wg0.conf | sort -n | tail -1)
    NEXT_IP=$((LAST_IP + 1))
    PORT=$(grep ListenPort /etc/wireguard/wg0.conf | awk '{print $3}')
    SERVER_PUB=$(grep PrivateKey /etc/wireguard/wg0.conf | head -n1 | awk '{print $3}' | wg pubkey)
    IP=$(curl -s icanhazip.com)

    # 添加到服务端
    cat >> /etc/wireguard/wg0.conf << EOF
[Peer]
PublicKey = $NEW_PUBLIC
AllowedIPs = 10.0.0.$NEXT_IP/32
EOF

    # 生成客户端文件
    cat > /etc/wireguard/client_$NEXT_IP.conf << EOF
[Interface]
PrivateKey = $NEW_PRIVATE
Address = 10.0.0.$NEXT_IP/24
DNS = 8.8.8.8
MTU = 1420

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $IP:$PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    # 重启生效
    systemctl restart wg-quick@wg0

    # 输出
    clear
    echo "====================================="
    echo " 新用户添加成功！IP：10.0.0.$NEXT_IP"
    echo "====================================="
    cat /etc/wireguard/client_$NEXT_IP.conf
    echo "====================================="
    qrencode -t ansiutf8 < /etc/wireguard/client_$NEXT_IP.conf
    echo "====================================="
    exit 0

# ======================
# 选项 3：查看所有用户
# ======================
elif [ "$ACTION" -eq 3 ]; then
    clear
    if [ ! -f /etc/wireguard/wg0.conf ]; then
        echo "错误：WireGuard 未安装！"
        exit 1
    fi

    echo "============================================="
    echo "            WireGuard 客户端列表"
    echo "============================================="
    echo " 序号 | 客户端IP地址"
    echo "============================================="
    grep -oP 'AllowedIPs = 10\.0\.0\.\K\d+' /etc/wireguard/wg0.conf | sort -n | awk '{print "  "NR"   | 10.0.0."$0}'
    echo "============================================="
    echo " 当前在线连接："
    wg show wg0 peers
    echo "============================================="
    exit 0

# ======================
# 选项 4：重启服务
# ======================
elif [ "$ACTION" -eq 4 ]; then
    clear
    systemctl restart wg-quick@wg0
    echo "====================================="
    echo " WireGuard 已重启完成！"
    echo " 运行状态：$(systemctl is-active wg-quick@wg0)"
    echo "====================================="
    exit 0

# ======================
# 选项 5：停止服务
# ======================
elif [ "$ACTION" -eq 5 ]; then
    clear
    systemctl stop wg-quick@wg0
    echo "====================================="
    echo " WireGuard 已停止！"
    echo " 运行状态：$(systemctl is-active wg-quick@wg0)"
    echo "====================================="
    exit 0

# ======================
# 选项 6：彻底卸载
# ======================
elif [ "$ACTION" -eq 6 ]; then
    clear
    read -p " 确定要彻底卸载 WireGuard 吗？所有配置会被删除 [y/n]：" CONFIRM
    if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
        clear
        echo "正在彻底卸载 WireGuard..."
        systemctl stop wg-quick@wg0 >/dev/null 2>&1
        systemctl disable wg-quick@wg0 >/dev/null 2>&1
        apt remove --purge -y wireguard wireguard-dkms wireguard-tools qrencode iptables-persistent >/dev/null 2>&1
        rm -rf /etc/wireguard >/dev/null 2>&1
        echo "====================================="
        echo " WireGuard 已彻底卸载完成！"
        echo "====================================="
    else
        echo "已取消卸载！"
    fi
    exit 0

else
    clear
    echo "输入错误！请输入 1-6 之间的数字！"
    exit 1
fi