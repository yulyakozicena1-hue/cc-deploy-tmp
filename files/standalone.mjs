// Постоянный сервер: отдаёт собранный фронт (dist/) и API на одном порту.
// Запуск: node server/standalone.mjs [порт]
import express from 'express';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApi } from './api.mjs';
import { startPolling } from './lib/sync.mjs';
import { startTelegramScheduler } from './lib/telegram.mjs';
import { startZpScheduler } from './lib/zp.mjs';
import { startNotifyBot } from './lib/notify-bot.mjs';
import { startFixwillPolling } from './lib/fixwill.mjs';
import { startSttScheduler } from './lib/stt.mjs';
import { startCallLogScheduler } from './lib/calllog.mjs';
import { startSmsScheduler } from './lib/sms.mjs';
// Google-график больше не ведётся — график живёт в дашборде.
// Модуль gsheet.mjs оставлен: данные октября уже в базе и служат подсказкой дней
// при добавлении сотрудника; ручной запуск синка — POST /api/schedule/sync.

const rootDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const port = Number(process.argv[2] ?? process.env.PORT ?? 7100);

const { app, db } = createApi(rootDir);
// index.html — всегда без кэша (браузер обязан переспросить), хэш-ассеты — годовой кэш
app.use(express.static(join(rootDir, 'dist'), {
  setHeaders(res, path) {
    if (path.endsWith('.html')) {
      res.setHeader('Cache-Control', 'no-store, must-revalidate');
    } else if (/[.-][0-9a-zA-Z_-]{8,}\.(js|css)$/.test(path)) {
      res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    }
  },
}));
app.get(/^\/(?!api\/).*/, (req, res) => res.sendFile(join(rootDir, 'dist', 'index.html')));

app.listen(port, () => {
  console.log(`Дашборд: http://localhost:${port}`);
  startPolling(db, 1); // раз в минуту: новые потенциальные заказы появляются быстро (плюс вебхук — мгновенно)
  startTelegramScheduler(db);
  startFixwillPolling(db, 10); // GPT-анализ звонков из панели FixWill
  startSttScheduler(db, 10); // собственная расшифровка записей (whisper)
  startCallLogScheduler(db, rootDir); // простые комментарии о звонках в РемОнлайн («Ответил»/«Пропущенный»/«Не дозвонились»)
  startSmsScheduler(db); // SMS канал Sms 5: входящие в базу + уведомления в группу чатов
  startZpScheduler(db);
  startNotifyBot(db);
});
