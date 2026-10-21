#!/bin/bash
# Обновление сервера 21.10 (SMS + АОН-списки + лента): замена api.mjs, sms.mjs, standalone.mjs
set -e
R="https://raw.githubusercontent.com/yulyakozicena1-hue/cc-deploy-tmp/main/files"
cd /opt/call-dash/app

echo "== Качаю api.mjs (gzip+base64) =="
curl -sL "$R/api.mjs.b64" -o /tmp/api.mjs.b64
base64 -d /tmp/api.mjs.b64 | gunzip > server/api.mjs.new
grep -q "smsDialog" server/api.mjs.new
grep -q "uis_aons_manual" server/api.mjs.new
node --check server/api.mjs.new
mv server/api.mjs.new server/api.mjs
echo "api.mjs заменён"

echo "== Качаю sms.mjs и standalone.mjs =="
curl -sL "$R/sms.mjs" -o server/lib/sms.mjs
curl -sL "$R/standalone.mjs" -o server/standalone.mjs
node --check server/lib/sms.mjs
node --check server/standalone.mjs
grep -q "startSmsScheduler" server/standalone.mjs
echo "файлы на месте"

echo "== Перезапуск дашборда =="
systemctl restart call-dash
sleep 3
systemctl is-active call-dash

echo "== Жду первый SMS-синк (до 2 минут) =="
sleep 100
node -e "const{DatabaseSync}=require('node:sqlite');const db=new DatabaseSync('data/dashboard.db');console.log('sms_chats:',db.prepare('SELECT COUNT(*) c FROM sms_chats').get().c,'| sms_messages:',db.prepare('SELECT COUNT(*) c FROM sms_messages').get().c);const t=db.prepare(\"SELECT value FROM kv WHERE key='sms_thread_id'\").get();console.log('группа SMS:', t?('создана, id '+t.value):'ещё нет');"
echo "== ГОТОВО =="
