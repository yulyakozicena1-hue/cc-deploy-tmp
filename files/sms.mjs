// SMS через канал Comagic «Sms 5» (chat channel id 30132).
// Чтение — публичный Data API (get.chats_report + get.chat_messages_report), проверено 21.10.
// Отправки в публичном API НЕТ — она идёт через внутренний API кабинета (go.comagic.ru,
// логин/пароль ЛК; хук заложен в sendSms, включится после ввода креда в Настройках).
import { getComagicToken } from './comagic.mjs';
import { encryptText, decryptText } from './secrets.mjs';

export const SMS_CHANNEL_ID = 30132; // «Sms 5» (active) — из get.chat_channels

const DATA_API = 'https://dataapi.comagic.ru/v2.0';
let reqId = 700;
async function cmCall(db, method, params = {}) {
  const token = getComagicToken(db);
  if (!token) throw new Error('Токен Comagic не настроен');
  const res = await fetch(DATA_API, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify({ jsonrpc: '2.0', id: reqId++, method, params: { access_token: token, ...params } }),
    signal: AbortSignal.timeout(30_000),
  });
  const json = await res.json();
  if (json.error) throw new Error(`Comagic ${method}: ${json.error.data?.mnemonic ?? json.error.message}`);
  return json.result?.data ?? json.result;
}

export function ensureSmsTables(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS sms_chats (
      chat_id INTEGER PRIMARY KEY,  -- id диалога в Comagic
      phone TEXT,                   -- телефон клиента
      channel_id INTEGER,
      employee_id INTEGER,
      date_time TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_sms_chats_phone ON sms_chats(phone);
    CREATE TABLE IF NOT EXISTS sms_messages (
      id INTEGER PRIMARY KEY,       -- id сообщения в Comagic
      chat_id INTEGER NOT NULL,
      direction TEXT NOT NULL,      -- in (от клиента) | out (наше)
      source TEXT,
      text TEXT,
      employee TEXT,
      date_time TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_sms_msg_chat ON sms_messages(chat_id, date_time);
  `);
}

const mskDay = (d) => {
  const t = new Date(d.getTime() + 3 * 3600e3);
  const p = (n) => String(n).padStart(2, '0');
  return `${t.getUTCFullYear()}-${p(t.getUTCMonth() + 1)}-${p(t.getUTCDate())} ${p(t.getUTCHours())}:${p(t.getUTCMinutes())}:${p(t.getUTCSeconds())}`;
};

// Группа в чатах дашборда для уведомлений о входящих SMS (создаётся один раз, все пользователи)
export function ensureSmsThread(db) {
  const row = db.prepare(`SELECT value FROM kv WHERE key = 'sms_thread_id'`).get();
  if (row?.value) return Number(row.value);
  const t = db.prepare(`INSERT INTO chat_threads (name, is_group, created_by, created_at) VALUES ('📨 SMS от клиентов', 1, 'system', ?)`)
    .run(new Date().toISOString());
  const tid = Number(t.lastInsertRowid);
  for (const u of db.prepare('SELECT id FROM users').all()) {
    db.prepare('INSERT OR IGNORE INTO chat_members (thread_id, user_id) VALUES (?, ?)').run(tid, u.id);
  }
  db.prepare(`INSERT OR REPLACE INTO kv (key, value) VALUES ('sms_thread_id', ?)`).run(String(tid));
  return tid;
}

// Один проход синхронизации: диалоги + сообщения канала Sms 5 + уведомления в группу
export async function syncSms(db) {
  ensureSmsTables(db);
  const now = new Date();
  const from = mskDay(new Date(now.getTime() - 3 * 86400e3));
  const till = mskDay(now);

  // Диалоги канала (телефон клиента по каждому chat_id)
  const chats = await cmCall(db, 'get.chats_report', { date_from: from, date_till: till, limit: 1000 });
  const insChat = db.prepare(`INSERT OR REPLACE INTO sms_chats (chat_id, phone, channel_id, employee_id, date_time) VALUES (?, ?, ?, ?, ?)`);
  for (const c of chats) {
    if (c.channel_id !== SMS_CHANNEL_ID) continue;
    insChat.run(c.id, c.visitor_phone_number ?? null, c.channel_id, c.employee_id ?? null, c.date_time ?? null);
  }

  // Сообщения канала за то же окно (дедуп по PK)
  const wm = Number(db.prepare(`SELECT value FROM kv WHERE key = 'sms_msg_wm'`).get()?.value ?? 0);
  const msgs = await cmCall(db, 'get.chat_messages_report', { date_from: from, date_till: till, limit: 3000 });
  const insMsg = db.prepare(`INSERT OR IGNORE INTO sms_messages (id, chat_id, direction, source, text, employee, date_time) VALUES (?, ?, ?, ?, ?, ?, ?)`);
  const chatPhone = new Map(db.prepare('SELECT chat_id, phone FROM sms_chats').all().map(r => [r.chat_id, r.phone]));
  let maxId = wm;
  const freshIn = [];
  for (const m of msgs) {
    if (m.channel_id !== SMS_CHANNEL_ID) continue;
    maxId = Math.max(maxId, m.id);
    const direction = m.source === 'visitor' || m.source === 'Посетитель' ? 'in' : 'out';
    const r = insMsg.run(m.id, m.chat_id, direction, m.source ?? null, m.text ?? null, m.employee_full_name ?? null, m.date_time ?? null);
    if (direction === 'in' && m.id > wm && r.changes > 0) freshIn.push(m);
  }
  db.prepare(`INSERT OR REPLACE INTO kv (key, value) VALUES ('sms_msg_wm', ?)`).run(String(maxId));

  // Уведомления о новых входящих в группу чатов (с номером заказа)
  if (freshIn.length) {
    const tid = ensureSmsThread(db);
    const insNote = db.prepare(`INSERT INTO chat_messages (thread_id, user_id, author, kind, text, created_at) VALUES (?, NULL, ?, 'text', ?, ?)`);
    for (const m of freshIn) {
      const phone = chatPhone.get(m.chat_id) ?? null;
      const order = phone ? db.prepare('SELECT id, number FROM orders WHERE client_phone = ? ORDER BY created_at DESC LIMIT 1').get(phone) : null;
      const head = order ? `Заказ №${order.number ?? order.id}` : (phone ? `+${phone}` : 'Клиент');
      insNote.run(tid, `📨 ${head}`, `Новое SMS от клиента:\n${m.text ?? ''}`.slice(0, 500), m.date_time ? new Date(String(m.date_time).replace(' ', 'T') + '+03:00').toISOString() : new Date().toISOString());
    }
  }
  return { chats: chats.length, messages: msgs.length, fresh: freshIn.length };
}

// Периодический запуск (каждые 2 минуты)
export function startSmsScheduler(db) {
  let running = false;
  const tick = async () => {
    if (running) return;
    running = true;
    try { const r = await syncSms(db); if (r.fresh) console.log(`[sms] новых входящих: ${r.fresh}`); }
    catch (e) { console.error('[sms] проход не удался:', e.message); }
    running = false;
  };
  setTimeout(tick, 90 * 1000);
  setInterval(tick, 2 * 60 * 1000);
  console.log('[sms] синхронизация канала Sms 5 запущена (каждые 2 мин)');
}

// Диалог с клиентом по телефону (для карточки заказа)
export function smsDialog(db, phone) {
  ensureSmsTables(db);
  return db.prepare(`
    SELECT m.id, m.direction, m.text, m.employee, m.date_time
    FROM sms_messages m JOIN sms_chats c ON c.chat_id = m.chat_id
    WHERE c.phone = ? ORDER BY m.date_time ASC LIMIT 300`).all(phone);
}

// ---------- Отправка (через внутренний API кабинета — включается кредами ЛК) ----------
// Креды: Настройки → Заказы → UIS (login/password ЛК Comagic, хранятся зашифрованно в kv comagic_lk).
export const saveLkCreds = (db, login, password) =>
  db.prepare(`INSERT OR REPLACE INTO kv (key, value) VALUES ('comagic_lk', ?)`)
    .run(encryptText(JSON.stringify({ login: String(login).trim(), password: String(password) })));
export const hasLkCreds = (db) => !!db.prepare(`SELECT value FROM kv WHERE key = 'comagic_lk'`).get()?.value;
const getLkCreds = (db) => {
  const v = db.prepare(`SELECT value FROM kv WHERE key = 'comagic_lk'`).get()?.value;
  return v ? JSON.parse(decryptText(v)) : null;
};

export async function sendSms(db, { phone, text }) {
  const creds = getLkCreds(db);
  if (!creds) {
    throw new Error('Отправка SMS пока не настроена: публичный API Comagic её не отдаёт (проверено). Нужен логин/пароль ЛК Comagic в Настройки → Заказы → UIS — тогда включится автоматически.');
  }
  // Вход во внутренний API кабинета (проверено: project='comagic' принимается)
  const loginRes = await fetch('https://go.comagic.ru/api/auth/json_rpc?method=login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'login', params: { login: creds.login, password: creds.password, project: 'comagic' } }),
    signal: AbortSignal.timeout(15_000),
  });
  const lj = await loginRes.json();
  const session = lj.result?.token ?? lj.result?.access_token ?? lj.result?.session_token;
  if (!session) throw new Error('ЛК Comagic: вход не удался — проверьте логин/пароль в Настройках');
  // TODO: путь отправки во внутреннем чат-API — уточняется после первого входа с кредами
  throw new Error('Вход в ЛК получен, но путь отправки ещё настраивается — сообщите разработчику (код SMS-LK-2)');
}
