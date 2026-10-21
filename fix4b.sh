#!/bin/bash
# Обновление сервера 21.10 (SMS): эндпоинты аонов/SMS + SMS в ленту + файлы + перезапуск
set -e
R="https://raw.githubusercontent.com/yulyakozicena1-hue/cc-deploy-tmp/main/files"
cd /opt/call-dash/app

echo "== Патчу api.mjs (часть 2) =="
python3 - << 'PYEOF'
import sys
def patch(path, old, new):
    s = open(path, encoding='utf-8').read()
    if new in s:
        print('  уже применено'); return
    if old not in s:
        print(f'  !! НЕ НАЙДЕН ЯКОРЬ: {old[:70]}…'); sys.exit(1)
    open(path, 'w', encoding='utf-8').write(s.replace(old, new, 1))
    print('  ok')

P = 'server/api.mjs'

# 1. эндпоинты: ручные АОН + SMS + креды ЛК — после call-info блока
patch(P,
"""      canCall: !!(isCallConfigured(db) && employeeId && aons.length),
    });
  });""",
"""      canCall: !!(isCallConfigured(db) && employeeId && aons.length),
    });
  });

  app.get('/api/uis/aons', auth, adminOnly, (req, res) => {
    let all = {};
    try { all = JSON.parse(db.prepare(`SELECT value FROM kv WHERE key = 'uis_aons_manual'`).get()?.value ?? '{}'); } catch {}
    res.json({ aons: all, map: uisMapGet(db) });
  });
  app.put('/api/uis/aons', auth, adminOnly, (req, res) => {
    try {
      const src = req.body?.aons;
      if (typeof src !== 'object' || src === null || Array.isArray(src)) {
        return res.status(400).json({ error: 'Нужен объект {userId: [{number, label}]}' });
      }
      const clean = {};
      for (const [uid, list] of Object.entries(src)) {
        if (!Array.isArray(list)) continue;
        clean[uid] = list.slice(0, 10).map(a => ({
          number: String(a?.number ?? '').replace(/\\D/g, '').slice(0, 12),
          label: a?.label ? String(a.label).slice(0, 40) : null,
        })).filter(a => a.number.length >= 10);
      }
      db.prepare(`INSERT OR REPLACE INTO kv (key, value) VALUES ('uis_aons_manual', ?)`).run(JSON.stringify(clean));
      audit(req, 'UIS: ручные АОН', `пользователей: ${Object.keys(clean).length}`);
      res.json({ ok: true });
    } catch (e) { res.status(400).json({ error: e.message }); }
  });

  // ---------- SMS с клиентом (канал Comagic «Sms 5») ----------
  app.get('/api/orders/live/:id/sms', auth, tabOnly('orders'), (req, res) => {
    try {
      const id = orderIdOf(req);
      if (!id) return res.status(400).json({ error: 'Некорректный номер заказа' });
      const local = db.prepare('SELECT client_phone FROM orders WHERE id = ?').get(id);
      const phone = local?.client_phone;
      if (!phone) return res.json({ items: [], phone: null });
      const isAdmin = req.user.role === 'admin';
      res.json({
        items: smsDialog(db, phone),
        phone: isAdmin ? phone : maskPhoneTail(phone),
        canSend: hasLkCreds(db),
      });
    } catch (e) { res.status(400).json({ error: e.message }); }
  });
  app.post('/api/orders/live/:id/sms', auth, tabOnly('orders'), async (req, res) => {
    try {
      const id = orderIdOf(req);
      if (!id) return res.status(400).json({ error: 'Некорректный номер заказа' });
      const text = String(req.body?.text ?? '').trim();
      if (!text) return res.status(400).json({ error: 'Пустое сообщение' });
      if (text.length > 800) return res.status(400).json({ error: 'Длинновато для SMS (максимум 800 знаков)' });
      const phone = db.prepare('SELECT client_phone FROM orders WHERE id = ?').get(id)?.client_phone;
      if (!phone) return res.status(400).json({ error: 'У заказа нет номера клиента' });
      await sendSms(db, { phone, text });
      audit(req, 'Заказ: SMS клиенту', `№${id}: ${text.slice(0, 80)}`);
      res.json({ ok: true });
    } catch (e) { res.status(400).json({ error: e.message }); }
  });
  app.put('/api/uis/lk', auth, adminOnly, (req, res) => {
    try {
      const login = String(req.body?.login ?? '').trim();
      const password = String(req.body?.password ?? '').trim();
      if (!login || !password) return res.status(400).json({ error: 'Нужны логин и пароль ЛК' });
      saveLkCreds(db, login, password);
      audit(req, 'UIS: сохранён кред ЛК Comagic (для SMS)', login);
      res.json({ ok: true });
    } catch (e) { res.status(400).json({ error: e.message }); }
  });""")

# 2. SMS в ленту заказа
patch(P,
"""      // Комментарии, написанные прямо в РемОнлайн (приходят вебхуком Comment.Created)
      for (const c of db.prepare('SELECT text, author, at FROM roapp_comments WHERE order_id = ? ORDER BY id').all(id)) {
        items.push({ at: c.at, kind: 'comment', text: c.text ?? '(комментарий)', login: c.author ? `${c.author} · РемОнлайн` : 'РемОнлайн' });
      }""",
"""      // Комментарии, написанные прямо в РемОнлайн (приходят вебхуком Comment.Created)
      for (const c of db.prepare('SELECT text, author, at FROM roapp_comments WHERE order_id = ? ORDER BY id').all(id)) {
        items.push({ at: c.at, kind: 'comment', text: c.text ?? '(комментарий)', login: c.author ? `${c.author} · РемОнлайн` : 'РемОнлайн' });
      }
      // SMS с клиентом (канал Sms 5): входящие и исходящие — в ленту заказа
      if (phone) {
        for (const m of db.prepare(`
          SELECT m.direction, m.text, m.employee, m.date_time FROM sms_messages m
          JOIN sms_chats c ON c.chat_id = m.chat_id WHERE c.phone = ?`).all(phone)) {
          const dt = new Date(String(m.date_time).replace(' ', 'T') + '+03:00');
          items.push({
            at: isNaN(dt) ? m.date_time : dt.toISOString(),
            kind: 'sms',
            direction: m.direction,
            text: m.text ?? '',
            login: m.direction === 'in' ? 'Клиент · SMS' : (m.employee ? `${m.employee} · SMS` : 'SMS'),
          });
        }
      }""")
print('патчи части 2 ок')
PYEOF

echo "== Качаю sms.mjs и standalone.mjs =="
curl -sL "$R/sms.mjs" -o server/lib/sms.mjs
curl -sL "$R/standalone.mjs" -o server/standalone.mjs
node --check server/api.mjs
node --check server/lib/sms.mjs
node --check server/standalone.mjs
grep -q "startSmsScheduler" server/standalone.mjs
echo "проверки ок"

echo "== Перезапуск дашборда =="
systemctl restart call-dash
sleep 3
systemctl is-active call-dash

echo "== Жду первый SMS-синк (до 2 минут) =="
sleep 100
node -e "const{DatabaseSync}=require('node:sqlite');const db=new DatabaseSync('data/dashboard.db');console.log('sms_chats:',db.prepare('SELECT COUNT(*) c FROM sms_chats').get().c,'| sms_messages:',db.prepare('SELECT COUNT(*) c FROM sms_messages').get().c);const t=db.prepare(\"SELECT value FROM kv WHERE key='sms_thread_id'\").get();console.log('группа SMS:', t?('создана id='+t.value):'ещё нет');"
echo "== ГОТОВО =="
