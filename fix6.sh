#!/bin/bash
# fix6.sh — диагностика и починка связки wstunnel -> sshd (порт 51234)
echo "=== Порты до ==="
ss -tlnp | grep -E ':(22|51234|8022)\b' || echo "(ничего из 22/51234/8022 не слушается)"

echo "=== Служба wstunnel ==="
systemctl is-active wstunnel || echo "wstunnel НЕ активна"
systemctl cat wstunnel 2>/dev/null | grep -E "ExecStart" || true

echo "=== Чиним sshd на 51234 ==="
mkdir -p /etc/ssh/sshd_config.d
printf 'Port 51234\n' > /etc/ssh/sshd_config.d/99-port.conf
grep -q 'sshd_config.d' /etc/ssh/sshd_config || sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
if sshd -t; then
  systemctl restart sshd
  echo "sshd перезапущен"
else
  echo "FAIL: sshd -t ошибка конфигурации"
  exit 1
fi
firewall-cmd --permanent --add-port=51234/tcp >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1 || true
sleep 1

echo "=== Порты после ==="
ss -tlnp | grep -E ':(22|51234|8022)\b' || echo "(пусто)"

if ss -tln | grep -q ':51234\b'; then
  echo "FIX6_SSH_OK"
else
  echo "FIX6_SSH_FAIL"
  systemctl status sshd --no-pager | tail -15
fi

echo "=== Проверка туннеля изнутри ==="
CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 8 \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==" \
  -H "Sec-WebSocket-Protocol: v1" \
  https://127.0.0.1/t7x9k2m4q8/events -H "Host: call-fixstat.ru")
echo "handshake -> $CODE (400 без валидного JWT — норма, главное не 200/502)"
echo "FIX6_DONE"
