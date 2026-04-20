#!/bin/bash
echo "适用没有入站的小鸡"
if [ "$EUID" -ne 0 ]; then
    echo "错误：请使用 root 权限运行此脚本。"
    exit 1
fi
uuid=$(cat /proc/sys/kernel/random/uuid)

# 依赖安装
PKGS="curl jq python3"

if command -v apt >/dev/null 2>&1; then
     apt update
     apt install -y $PKGS
elif command -v dnf >/dev/null 2>&1; then
     dnf install -y $PKGS
elif command -v yum >/dev/null 2>&1; then
     yum install -y $PKGS
elif command -v pacman >/dev/null 2>&1; then
     pacman -Sy --noconfirm $PKGS
elif command -v zypper >/dev/null 2>&1; then
     zypper install -y $PKGS
elif command -v apk >/dev/null 2>&1; then
     apk add $PKGS
else
    echo "不支持的包管理器"
    exit 1
fi

# 生成节点名
name_response=$(curl -s --max-time 5 http://ip-api.com/json/ || echo "{}")
countryCode=$(echo "$name_response" | jq -r '.countryCode // empty')
cityinfo=$(echo "$name_response" | jq -r '.city // "Unknown"')
flag=$(python3 -c "print(''.join(chr(127397 + ord(c)) for c in '$countryCode'))" 2>/dev/null || echo "🌐")

proxy_name="${flag}${cityinfo} CF"

if ! command -v cloudflared &>/dev/null; then
    echo "未检测到 cloudflared，正在开始安装..."
    curl -fsSL https://link.wdqgn.eu.org/nopasswd/pkg/cloudflared-pkg.sh | bash
else
    echo "[+] 已检测到 cloudflared，跳过安装。"
fi

# 请求生成隧道配置
curl -fsSL https://link.wdqgn.eu.org/nopasswd/cftunnel-client.sh | bash
source /tmp/tunnel.env

if ! command -v mihomo &>/dev/null; then
    echo "未检测到 mihomo，正在开始安装..."
    curl -fsSL https://link.wdqgn.eu.org/nopasswd/pkg/mihomo-pkg.sh | bash
else
    echo "[+] 已检测到 mihomo，跳过安装。"
fi

vless_x25519=$(mihomo generate vless-x25519)
server_decryption=$(echo "$vless_x25519" | awk -F'"' '/\[Server\]/ {print $2}')
client_encryption=$(echo "$vless_x25519" | awk -F'"' '/\[Client\]/ {print $2}')
mkdir -p /etc/mihomo
cat > /etc/mihomo/config.yaml <<EOF
external-controller: "127.0.0.1:9090"
external-ui: ui
secret: "$uuid"
external-ui-url: "https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip"
ipv6: true
log-level: info
mode: rule
dns:
  enable: false
listeners:
  - name: vless-ws-in
    type: vless
    listen: 127.0.0.1
    port: 54999
    users:
      - username: 1
        uuid: $uuid
        flow: xtls-rprx-vision
    decryption: $server_decryption
    ws-path: /$uuid-vl
proxy-groups:
  - name: "DIRECT-OUT"
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,DIRECT
EOF
current_time=$(TZ=UTC-8 date +"%Y%m%d-%H%M")
mkdir -p /opt/www
cat > /opt/www/${current_time}.yaml <<EOF
proxies:
- {name: "$proxy_name", type: vless, server: cf.wdqgn.eu.org, port: 443, uuid: $uuid, network: ws, tls: true, ech-opts: {enable: true}, flow: xtls-rprx-vision, alpn: ["h2","http/1.1"], ws-opts: {path: /$uuid-vl, headers: {host: $domain_name}}, encryption: $client_encryption}
EOF

wget -O /opt/www/config.yaml https://link.wdqgn.eu.org/nopasswd/config.yaml
subscription_address=https://${domain_name_api}/${current_time}.yaml
sed -i "s#my-subscription-address#$(printf '%s' "$subscription_address" | sed 's/[\/&]/\\&/g')#g" /opt/www/config.yaml
sed -i "s#password-config#$uuid#g" /opt/www/config.yaml


if command -v systemctl &>/dev/null; then
    cloudflared service install
    systemctl daemon-reload
    systemctl enable --now mihomo
    systemctl status mihomo --no-pager
else
    cloudflared service install
    rc-update add mihomo default
    rc-service mihomo restart
fi

cat /opt/www/${current_time}.yaml
echo "生成的clash配置位于 /opt/www/"
echo "clash订阅链接地址为,可直接使用 https://$domain_name_api/config.yaml"
echo "纯节点链接,可加入其他配置的proxy-providers块 $subscription_address   "
echo "使用订阅需先关闭mihomo端口占用,临时开启文件服务器到/opt/www/"
echo "systemctl stop mihomo 或 rc-service mihomo stop"
echo "python3 -m http.server 9090 --bind 127.0.0.1 --directory /opt/www/"
echo "更新订阅后,关闭临时http服务,重新启动mihomo即可,systemctl restart mihomo 或 rc-service mihomo restart"
echo "访问控制zashboard面板,地址为 https://$domain_name_api/ui/#/"
echo "面板配置,协议 https 主机 $domain_name_api 端口 443 密码 $uuid"
echo "非移动用户自行更换其他优选域名,cf.wdqgn.eu.org只测了移动"
echo "如遇意外错误可加入tg群反馈 https://t.me/dmjlqa"