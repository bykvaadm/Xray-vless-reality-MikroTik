#!/bin/sh
XRAY_CONF_PATH="/usr/local/etc/xray/config.json"
echo "Starting setup container please wait"
sleep 1

SERVER_IP_ADDRESS="$(nslookup $SERVER_IP_ADDRESS 8.8.8.8 | awk '/Address: / && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $2}' | tail -n1)"
NET_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|tun' | head -n1 | cut -d'@' -f1)

ip tuntap del mode tun dev tun0 || true
ip tuntap add mode tun dev tun0
ip addr add 172.31.200.10/30 dev tun0
ip link set dev tun0 up
ip route del default via 172.18.20.5 || true
ip route add default via 172.31.200.10
ip route add "${SERVER_IP_ADDRESS}/32" via 172.18.20.5

echo "nameserver 172.18.20.5" > /etc/resolv.conf

cat <<EOF > "${XRAY_CONF_PATH}"
{
  "log": {
    "loglevel": "silent"
  },
  "inbounds": [
    {
      "port": 10800,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$SERVER_ADDRESS",
            "port": $SERVER_PORT,
            "users": [
              {
                "id": "$USER_ID",
                "encryption": "$ENCRYPTION",
                "flow": "$FLOW"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "$FINGERPRINT_FP",
          "serverName": "$SERVER_NAME_SNI",
          "publicKey": "$PUBLIC_KEY_PBK",
          "spiderX": "$SPIDERX",
          "shortId": "$SHORT_ID_SID"
        },
        "xhttpSettings": {
          "path": "/",
          "mode": "auto"
        }
      },
      "tag": "proxy"
    }
  ]
}
EOF

#TODO
echo "Start Xray core"
/usr/local/bin/xray run -config "${XRAY_CONF_PATH}" &
echo "Start tun2socks"
/usr/bin/tun2socks -loglevel silent -tcp-sndbuf 3m -tcp-rcvbuf 3m -device tun0 -proxy socks5://127.0.0.1:10800 -interface "${NET_IFACE}" &
echo "Container customization is complete"
