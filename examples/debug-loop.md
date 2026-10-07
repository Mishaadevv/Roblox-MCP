# Пример: цикл отладки «запустил → прочитал → починил»

> Ты: Проверь игру и почини ошибки.

Агент:

1. `clear_output` — чистый лог
2. `play_solo` — запускает Play Solo (F5)
3. ждёт ~5 секунд (пауза клиента)
4. `get_output` (`limit: 100`) — читает ошибки и принты
5. `get_play_state` — убедиться, что тест идёт
6. Находит ошибку, например `Workspace.Script:3: attempt to index nil`:
   - `read_script` (`Workspace.Script`)
   - `write_script` с исправлением
7. `stop_playtest` → `play_solo` снова → `get_output` — убедиться, что чисто
8. `stop_playtest`, отчёт пользователю

Всё это агент делает сам, без участия человека — в этом и смысл `roblox-mcp`.
