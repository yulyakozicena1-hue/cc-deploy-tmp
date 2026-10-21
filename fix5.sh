#!/bin/bash
# fix5.sh — чинит туннель wstunnel: location был точным (= /t7x9k2m4q8),
# а клиент ходит на /t7x9k2m4q8/events. Делаем префиксный location.
set -e
CONF=/etc/nginx/conf.d/call-dash.conf
cp -a "$CONF" "$CONF.bak-fix5-$(date +%s)"

if grep -q "location = /t7x9k2m4q8" "$CONF"; then
  sed -i 's|location = /t7x9k2m4q8|location /t7x9k2m4q8|g' "$CONF"
  echo "PATCHED: location стал префиксным"
elif grep -q "location /t7x9k2m4q8" "$CONF"; then
  echo "OK: location уже префиксный"
else
  echo "FAIL: location /t7x9k2m4q8 не найден в $CONF"
  exit 1
fi

nginx -t || { echo "FAIL: nginx -t"; exit 1; }
systemctl reload nginx
sleep 1

CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 8 https://127.0.0.1/t7x9k2m4q8/events -H "Host: call-fixstat.ru")
echo "CHECK /t7x9k2m4q8/events -> $CODE (нужно 400)"
if [ "$CODE" = "400" ]; then
  echo "FIX5_OK"
else
  echo "FIX5_BAD_CODE"
fi
