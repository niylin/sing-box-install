#!/usr/bin/env bash
echo "欢迎使用 mihomo 一键安装脚本！"
echo "本脚本将安装 mihomo，并配置 hysteria,reality，anytls"
echo "生成的客户端配置中，ip地址将配置为当前服务器的出站IP，如果出站和入站IP不同，请手动修改客户端配置文件"
while true; do
    echo "请选择使用的IP地址类型："
    echo "[1] IPv6"
    echo "[2] IPv4"
    read -p "请输入选项数字 [1/2]: " ip_type_choice < /dev/tty
    case "$ip_type_choice" in
        1|2) break ;;
        *) echo "错误：无效选项 '$ip_type_choice'，请输入 1 或 2。" ;;
    esac
done

while true; do
    read -p "请输入 hysteria 端口 (例如 58999, reality为该值+10, anytls为该值+20): " hysteria_port < /dev/tty
    if [[ "$hysteria_port" =~ ^[0-9]+$ ]] && [ "$hysteria_port" -le 65533 ]; then
        break
    fi
    echo "错误：请输入有效的端口号数字 (1-65533)。"
done

MASQUE_API_URL="https://masque-api.wdqgn.eu.org/?json=masque-config"
while true; do
    read -rp "是否要配置 Warp 节点出站? (y/n) " choice < /dev/tty
    case "$choice" in
        n|N)
            echo "跳过 Warp 节点配置。"
            break
            ;;
        y|Y)
            while true; do
                echo "尝试从 API 获取 Warp 配置..."
                masque_response=$(curl -s --fail "$MASQUE_API_URL")
                if [[ $? -ne 0 || -z "$masque_response" ]]; then
                    echo "$masque_response"
                    echo "获取失败！，API有20秒的请求速率限制。"
                    read -rp "是否重试? (y/n) " retry_choice < /dev/tty
                    if [[ "$retry_choice" =~ ^[nN]$ ]]; then
                        echo "跳过 Warp 节点配置。"
                        break 2
                    else
                        continue
                    fi
                fi

                # 提取字段
                MASQUE_IP=$(echo "$masque_response" | jq -r '.ip')
                MASQUE_IPV6=$(echo "$masque_response" | jq -r '.ipv6')
                MASQUE_PRIVATE_KEY=$(echo "$masque_response" | jq -r '.["private-key"]')
                MASQUE_PUBLIC_KEY=$(echo "$masque_response" | jq -r '.["public-key"]')
                # 检查是否获取到有效数据
                if [[ -z "$MASQUE_IP" || -z "$MASQUE_IPV6" || -z "$MASQUE_PRIVATE_KEY" || -z "$MASQUE_PUBLIC_KEY" ]]; then
                    echo "$masque_response"
                    echo "API 返回内容不完整！，API有20秒的请求速率限制"
                    read -rp "是否重试? (y/n) " retry_choice < /dev/tty
                    if [[ "$retry_choice" =~ ^[nN]$ ]]; then
                        echo "跳过 Warp 节点配置。"
                        break 2
                    else
                        continue
                    fi
                fi
                echo "Warp 配置获取成功:"
                MASQUE_CONFIG_STATUS="success"
                break 2
            done
            ;;
        *)
            echo "请输入 y 或 n"
            ;;
    esac
done

reality_port=$((hysteria_port + 10))
anytls_port=$((hysteria_port + 20))

set -e
APT_PKGS="curl wget nano jq cron python3 openssl"
APK_PKGS="curl wget nano jq dcron python3 openssl"
PKGS="curl wget nano jq cronie  python3 openssl"
# 先安装依赖
if command -v apt >/dev/null 2>&1; then
     apt update
     apt install -y $APT_PKGS
elif command -v dnf >/dev/null 2>&1; then
     dnf install -y $PKGS
elif command -v yum >/dev/null 2>&1; then
     yum install -y $PKGS
elif command -v pacman >/dev/null 2>&1; then
     pacman -Sy --noconfirm $PKGS
elif command -v zypper >/dev/null 2>&1; then
     zypper install -y $APT_PKGS
elif command -v apk >/dev/null 2>&1; then
     apk add $APK_PKGS
else
    echo "不支持的包管理器"
    exit 1
fi


# 获取本机IP
if [ "$ip_type_choice" == "1" ]; then
    ipv6_address=$(curl -sL  https://ipv6.ping0.cc)
    ip_address=$ipv6_address
    MASQUE_ENDIP=masque6.wdqgn.eu.org
elif [ "$ip_type_choice" == "2" ]; then
    ipv4_address=$(curl -sL "https://ipv4.ping0.cc")
    ip_address=$ipv4_address
    MASQUE_ENDIP=masque.wdqgn.eu.org
fi

# 检查 mihomo 是否在系统路径中
if ! command -v mihomo &>/dev/null; then
    echo "未检测到 mihomo，正在开始安装..."
    curl -fsSL https://link.wdqgn.eu.org/nopasswd/mihomo-pkg.sh | bash
else
    echo "[+] 已检测到 mihomo，跳过安装。"
fi

current_time=$(TZ=UTC-8 date +"%Y%m%d-%H%M")
Certificate_name="bnm.uw.to"

# 生成密钥
shortId=$(openssl rand -hex 8)
output=$(mihomo generate reality-keypair)

private_key=$(echo "$output" | awk '/PrivateKey:/ {print $2}')
public_key=$(echo "$output" | awk '/PublicKey:/ {print $2}')
uuid=$(cat /proc/sys/kernel/random/uuid)
echo "$shortId"
echo "$private_key"
echo "$public_key"

# 生成节点名
name_response=$(curl -s --max-time 5 http://ip-api.com/json/ || echo "{}")
countryCode=$(echo "$name_response" | jq -r '.countryCode // empty')
cityinfo=$(echo "$name_response" | jq -r '.city // "Unknown"')
flag=$(python3 -c "print(''.join(chr(127397 + ord(c)) for c in '$countryCode'))" 2>/dev/null || echo "🌐")

proxy_name="${flag}${cityinfo} CF"
HY_proxy_name=${proxy_name/CF/HY}
RE_proxy_name=${proxy_name/CF/RE}
AN_proxy_name=${proxy_name/CF/AN}
# 证书
mkdir -p /etc/mihomo/cert

wget -N -O /etc/mihomo/cert/$Certificate_name.crt "https://link.wdqgn.eu.org/nopasswd/$Certificate_name.crt"
wget -N -O /etc/mihomo/cert/$Certificate_name.key "https://link.wdqgn.eu.org/nopasswd/$Certificate_name.key"

mkdir -p /etc/mihomo
CONFIG_FILE="/etc/mihomo/config.yaml"
cat > "$CONFIG_FILE" <<EOF
ipv6: true
dns:
  enable: false
listeners:
- name: anytls-in
  type: anytls
  port: $anytls_port
  listen: 0.0.0.0
  users:
    username1: $uuid
  certificate: /etc/mihomo/cert/$Certificate_name.crt
  private-key: /etc/mihomo/cert/$Certificate_name.key
- name: vless-reality-in
  type: vless
  port: $reality_port
  listen: 0.0.0.0
  users:
  - uuid: $uuid
    username: 1
    flow: xtls-rprx-vision
  reality-config:
    dest: www.tencentcloud.com:443
    private-key: $private_key
    short-id:
      - $shortId
    server-names:
      - www.tencentcloud.com
- name: hy2-in
  type: hysteria2
  port: $hysteria_port
  listen: 0.0.0.0
  users:
    user1: $uuid
  up: 1000
  down: 1000
  certificate: /etc/mihomo/cert/$Certificate_name.crt
  private-key: /etc/mihomo/cert/$Certificate_name.key

proxy-groups:
- name: "DIRECT-OUT"
  type: select
  proxies:
    #- warpped-masque
    - DIRECT
rules:
  - MATCH,DIRECT-OUT
EOF


cat > ~/link.yaml <<EOF
-----------------------------------------------------------------
-----------------------------------------------------------------
- {name: "${HY_proxy_name} |${current_time}", type: hysteria2, server: $ip_address, port: $hysteria_port, password: $uuid, sni: $Certificate_name, alpn: [h3]}
- {name: "${RE_proxy_name} |${current_time}", type: vless, server: $ip_address, port: $reality_port, uuid: $uuid, network: tcp, tls: true, udp: true, flow: xtls-rprx-vision, servername: www.tencentcloud.com, reality-opts: {public-key: $public_key, short-id: $shortId}, client-fingerprint: chrome}
- {name: "${AN_proxy_name} |${current_time}", type: anytls, server: $ip_address, port: $anytls_port, password: $uuid, client-fingerprint: chrome, udp: true, idle-session-check-interval: 30, idle-session-timeout: 30, min-idle-session: 0, sni: $Certificate_name, alpn: [h2, http/1.1], skip-cert-verify: true}
EOF



cat ~/link.yaml

if command -v crontab &>/dev/null; then
(crontab -l 2>/dev/null; \
echo "0 0 * * 0 wget -N -O /etc/mihomo/cert/$Certificate_name.crt https://link.wdqgn.eu.org/nopasswd/$Certificate_name.crt"; \
echo "0 0 * * 0 wget -N -O /etc/mihomo/cert/$Certificate_name.key https://link.wdqgn.eu.org/nopasswd/$Certificate_name.key") | crontab -
else
    echo "未检测到 crontab，请手动设置定时任务更新证书"
    echo "wget -N -O /etc/mihomo/cert/$Certificate_name.crt https://link.wdqgn.eu.org/nopasswd/$Certificate_name.crt"
    echo "wget -N -O /etc/mihomo/cert/$Certificate_name.key https://link.wdqgn.eu.org/nopasswd/$Certificate_name.key"
fi

if command -v systemctl &>/dev/null; then
    systemctl daemon-reload
    systemctl enable --now mihomo
    systemctl status mihomo --no-pager
else
    rc-update add mihomo default
    rc-service mihomo restart
fi
if [[ "$MASQUE_CONFIG_STATUS" = "success" ]]; then
cat >> "$CONFIG_FILE" <<EOF

proxies:
- {name: "warpped-masque", type: masque, server: $MASQUE_ENDIP, port: 443, private-key: "$MASQUE_PRIVATE_KEY", public-key: "$MASQUE_PUBLIC_KEY", ip: $MASQUE_IP, ipv6: $MASQUE_IPV6, mtu: 1280, udp: true}
EOF
sed -i 's/#//g' "$CONFIG_FILE"
echo "已更新 $CONFIG_FILE，已启用 warpped-masque出站"
fi

echo "如果开启warp无法连接，尝试将/etc/mihomo/config.yaml中的rules:  - MATCH,DIRECT-OUT 更改为rules:  - MATCH,DIRECT",即可取消warp带来的影响
