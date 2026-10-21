#!/bin/bash
# Обновление сервера без SSH: точечные патчи + пересборка фронта (21.10)
set -e
cd /opt/call-dash/app
echo "== Патчу исходники =="
python3 - << 'PYEOF'
import sys
def patch(path, old, new, must=True):
    s = open(path, encoding='utf-8').read()
    if new in s:
        print(f'  уже применено: {path}'); return
    if old not in s:
        print(f'  !! НЕ НАЙДЕН ЯКОРЬ в {path}'); sys.exit(1) if must else None; return
    open(path, 'w', encoding='utf-8').write(s.replace(old, new, 1))
    print(f'  ok: {path}')

# 1. STT: whisper под nice 19
patch('server/lib/stt.mjs',
  "const VAD_MODEL = '/opt/whisper.cpp/models/for-tests-silero-v6.2.0-ggml.bin';",
  "const VAD_MODEL = '/opt/whisper.cpp/models/for-tests-silero-v6.2.0-ggml.bin';\nconst runWhisper = (args, opts) => run('nice', ['-n', '19', WHISPER, ...args], opts);")
patch('server/lib/stt.mjs',
  'const { stdout } = await run(WHISPER, [',
  'const { stdout } = await runWhisper([')

# 2. Лента: без висячей запятой в записи о звонке
patch('server/api.mjs',
  "if (text.startsWith(':')) text = text.slice(1).trim();",
  "if (text.startsWith(':') || text.startsWith(',') || text.startsWith('·')) text = text.slice(1).trim();")

# 3. Лента заказа: хронология (старые сверху) + автопрокрутка к последнему
patch('src/components/ClientCard.tsx',
  """function OrderFeed({ orderId, reloadKey }: { orderId: number; reloadKey: number }) {
  const [items, setItems] = useState<any[] | null>(null);
  useEffect(() => {
    api(`/api/orders/live/${orderId}/feed`).then(d => setItems(d.items ?? [])).catch(() => setItems([]));
  }, [orderId, reloadKey]);""",
  """function OrderFeed({ orderId, reloadKey }: { orderId: number; reloadKey: number }) {
  const [items, setItems] = useState<any[] | null>(null);
  const rootRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    api(`/api/orders/live/${orderId}/feed`).then(d => setItems((d.items ?? []).slice().reverse())).catch(() => setItems([]));
  }, [orderId, reloadKey]);
  useEffect(() => {
    if (items === null) return;
    const sc = rootRef.current?.parentElement;
    if (sc) sc.scrollTop = sc.scrollHeight;
  }, [items]);""")
patch('src/components/ClientCard.tsx',
  '<div className="px-4 py-3">\n      <div className="text-[10.5px] uppercase tracking-wider text-slate-400 mb-2">История заказа</div>',
  '<div className="px-4 py-3" ref={rootRef}>\n      <div className="text-[10.5px] uppercase tracking-wider text-slate-400 mb-2">История заказа</div>')
print('патчи применены')
PYEOF

echo "== Зависимости для сборки =="
npm ci --no-audit --no-fund --silent
echo "== Сборка фронта =="
npm run build
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

echo "== fail2ban =="
systemctl enable --now fail2ban || true

echo "== ГОТОВО: обновление применено =="
