#!/bin/bash
# fix-ssh443b: вставляем location туннеля в 443 server-блок nginx
set -e
cd /etc/nginx/conf.d

echo "== Структура call-dash.conf =="
grep -n "listen\|server {" call-dash.conf | head -10

python3 - << 'PYEOF'
import sys
p = 'call-dash.conf'
s = open(p, encoding='utf-8').read()
if '/t7x9k2m4q8' in s:
    print('location уже вставлен'); sys.exit(0)

LOC = """
    location = /t7x9k2m4q8 {
      proxy_pass http://127.0.0.1:8022;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection \"upgrade\";
      proxy_set_header Host $host;
      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
      proxy_connect_timeout 30s;
    }
"""

# находим server-блок, в котором есть 443, с балансом скобок
def find_server_block(text, needle):
    pos = 0
    while True:
        i = text.find('server {', pos)
        if i == -1: return None
        depth = 0
        j = i
        while j < len(text):
            c = text[j]
            if c == '{': depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    block = text[i:j]
                    if needle in block:
                        return (i, j)
                    break
            j += 1
        pos = i + 1
    return None

blk = find_server_block(s, '443')
if not blk:
    print('!! server-блок с 443 не найден'); sys.exit(1)
start, endbrace = blk
# вставляем location перед закрывающей скобкой блока
new = s[:endbrace] + LOC + s[endbrace:]
open(p, 'w', encoding='utf-8').write(new)
print('location вставлен в 443-блок')
PYEOF

echo "== удаляю ошибочный файл =="
rm -f /etc/nginx/conf.d/ssh-ws.conf
nginx -t && systemctl reload nginx && echo "== ГОТОВО: nginx перезагружен с туннелем =="
systemctl is-active wstunnel
