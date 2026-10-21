#!/bin/bash
# Обновление сервера 21.10 (SMS + ручные АОН): патчи api.mjs + новые файлы
set -e
R="https://raw.githubusercontent.com/yulyakozicena1-hue/cc-deploy-tmp/main/files"
cd /opt/call-dash/app

echo "== Патчу api.mjs =="
python3 - << 'PYEOF'
import sys
def patch(path, old, new):
    s = open(path, encoding='utf-8').read()
    if new.split('\n')[0] in s and new in s:
        print(f'  уже применено ({path})'); return
    if old not in s:
        print(f'  !! НЕ НАЙДЕН ЯКОРЬ: {old[:70]}…'); sys.exit(1)
    open(path, 'w', encoding='utf-8').write(s.replace(old, new, 1))
    print('  ok')

P = 'server/api.mjs'

# 1. импорт sms-модуля
patch(P,
"import { isCallConfigured, startEmployeeCall, uisEmployees, uisVirtualNumbers, uisMapGet, uisMapSave, uisVirtualNumber } from './lib/uis-call.mjs';",
"import { isCallConfigured, startEmployeeCall, uisEmployees, uisVirtualNumbers, uisMapGet, uisMapSave, uisVirtualNumber } from './lib/uis-call.mjs';\nimport { smsDialog, sendSms, saveLkCreds, hasLkCreds } from './lib/sms.mjs';")

# 2. функция ручных АОН перед call-info
patch(P,
"  app.get('/api/orders/call-info', auth, tabOnly('orders'), async (req, res) => {",
"""  // Ручной список АОН по пользователям (kv uis_aons_manual {userId: [{number, label}]})
  const uisAonsManual = (db, userId) => {
    try {
      const all = JSON.parse(db.prepare(`SELECT value FROM kv WHERE key = 'uis_aons_manual'`).get()?.value ?? '{}');
      return (all[userId] ?? [])
        .map(a => ({ number: String(a?.number ?? '').replace(/\\D/g, ''), label: a?.label ? String(a.label).slice(0, 40) : null }))
        .filter(a => a.number.length >= 10);
    } catch { return []; }
  };
  app.get('/api/orders/call-info', auth, tabOnly('orders'), async (req, res) => {""")

# 3. ручной список — приоритет в call-info
patch(P,
"""    // Номера «с какого позвонить» — те, что разрешены сотруднику в карточке UIS (кэш uis_employees)
    let aons = [];
    if (employeeId) {""",
"""    // Номера «с какого позвонить»: 1) ручной список из Настроек (приоритет),
    // 2) разрешённые сотруднику в UIS (если API их отдало), 3) номер по умолчанию.
    let aons = uisAonsManual(db, req.user.id);
    if (!aons.length && employeeId) {""")

# 4. ручной список — приоритет при старте звонка
patch(P,
"""      if (wantVn) {
        const emps = await uisEmployees(db, async () => []).catch(() => []);
        const me = emps.find(e => e.id === employeeId);
        const allowed = (me?.aons ?? []).map(a => String(typeof a === 'string' ? a : a.number).replace(/\\D/g, ''));
        if (allowed.length && !allowed.includes(wantVn)) {
          return res.status(403).json({ error: 'Этот номер вам не разрешён в UIS' });
        }
        virtualNumber = wantVn;
      }""",
"""      if (wantVn) {
        const manual = uisAonsManual(db, req.user.id).map(a => a.number);
        let uisAons = [];
        if (!manual.length) {
          const emps = await uisEmployees(db, async () => []).catch(() => []);
          const me = emps.find(e => e.id === employeeId);
          uisAons = (me?.aons ?? []).map(a => String(typeof a === 'string' ? a : a.number).replace(/\\D/g, ''));
        }
        const allowed = manual.length ? manual : uisAons;
        if (allowed.length && !allowed.includes(wantVn)) {
          return res.status(403).json({ error: 'Этот номер вам не разрешён — выбирайте из списка в карточке' });
        }
        virtualNumber = wantVn;
      }""")
print('патчи ядра ок')
PYEOF

echo "== Конец первой части — вторая в fix4b =="
