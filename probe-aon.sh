#!/bin/bash
# Разведка полей сотрудника UIS (где лежат разрешённые АОН)
cd /opt/call-dash/app
node -e "
const{DatabaseSync}=require('node:sqlite');
const db=new DatabaseSync('data/dashboard.db');
const v=db.prepare(\"SELECT value FROM kv WHERE key='uis_emp_raw'\").get();
if (!v) { console.log('uis_emp_raw ПУСТ — кэш ещё не обновлялся сырым объектом'); }
else {
  const e = JSON.parse(v.value);
  console.log('ПОЛЯ:', Object.keys(e).join(', '));
  console.log('ЗНАЧЕНИЕ:', JSON.stringify(e, null, 1).slice(0, 3500));
}
"
