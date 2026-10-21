#!/bin/bash
# Финиш обновления 21.10: перезапуск с новыми патчами + swap + fail2ban
cd /opt/call-dash/app
echo "== Проверяю патчи =="
grep -c runWhisper server/lib/stt.mjs && echo "nice-патч на месте"
grep -c "startsWith('·')" server/api.mjs && echo "запятая-патч на месте"

echo "== Перезапуск дашборда =="
systemctl restart call-dash
sleep 3
systemctl is-active call-dash

echo "== swap 2G =="
if ! swapon --show | grep -q swapfile; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q swapfile /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "swap создан"
else echo "swap уже есть"; fi
free -m | head -2

echo "== fail2ban =="
systemctl enable --now fail2ban || true
fail2ban-client status sshd 2>/dev/null | grep -E "Currently|Total" || true

echo "== ГОТОВО =="
