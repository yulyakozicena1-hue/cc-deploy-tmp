#!/bin/bash
# SSH через 443 (wstunnel) — обход исходящего фильтра «только 443»
set -e
cd /tmp

echo "== wstunnel бинарь =="
curl -sL -o wst.tgz "https://github.com/erebe/wstunnel/releases/download/v11.1.0/wstunnel_11.1.0_linux_amd64.tar.gz"
tar xzf wst.tgz
install -m 755 wstunnel /usr/local/bin/wstunnel
NO_COLOR=false wstunnel --version

echo "== systemd служба =="
cat > /etc/systemd/system/wstunnel.service << 'UNIT'
[Unit]
Description=wstunnel: SSH через 443 (websocket)
After=network.target nginx.service

[Service]
Environment=NO_COLOR=false
ExecStart=/usr/local/bin/wstunnel server ws://127.0.0.1:8022 --restrict-to 127.0.0.1:51234 --restrict-http-upgrade-path-prefix /t7x9k2m4q8
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now wstunnel
systemctl is-active wstunnel

echo "== nginx: endpoint для туннеля =="
cat > /etc/nginx/conf.d/ssh-ws.conf << 'NGX'
location = /t7x9k2m4q8 {
  proxy_pass http://127.0.0.1:8022;
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection "upgrade";
  proxy_set_header Host $host;
  proxy_read_timeout 3600s;
  proxy_send_timeout 3600s;
  proxy_connect_timeout 30s;
}
NGX
nginx -t
systemctl reload nginx
echo "== ГОТОВО: туннель живёт на wss://call-fixstat.ru/t7x9k2m4q8 =="
