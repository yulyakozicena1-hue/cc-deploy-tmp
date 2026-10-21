#!/bin/bash
# fix7.sh — убирает у wstunnel ограничение префикса пути (nginx уже фильтрует
# по секретному пути /t7x9k2m4q8), оставляет --restrict-to 127.0.0.1:51234.
echo "=== Старый ExecStart ==="
systemctl cat wstunnel | grep ExecStart

cp -a /etc/systemd/system/wstunnel.service /etc/systemd/system/wstunnel.service.bak-fix7 2>/dev/null || true

cat > /etc/systemd/system/wstunnel.service <<'EOF'
[Unit]
Description=wstunnel server (SSH via 443)
After=network.target

[Service]
ExecStart=/usr/local/bin/wstunnel server ws://127.0.0.1:8022 --restrict-to 127.0.0.1:51234
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl restart wstunnel
sleep 1
systemctl is-active wstunnel || { echo "FAIL: wstunnel не поднялся"; journalctl -u wstunnel --no-pager | tail -10; exit 1; }

echo "=== Сквозной тест внутри сервера (клиент -> wstunnel -> sshd) ==="
timeout 10 /usr/local/bin/wstunnel client -L tcp://2299:127.0.0.1:51234 ws://127.0.0.1:8022 >/tmp/wst-test.log 2>&1 &
sleep 2
BANNER=$(timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/2299 && head -c 7 <&3' 2>/dev/null || true)
pkill -f "tcp://2299" 2>/dev/null
echo "banner: [$BANNER]"
if echo "$BANNER" | grep -q "SSH-"; then
  echo "FIX7_OK"
else
  echo "FIX7_FAIL"
  tail -8 /tmp/wst-test.log
fi
