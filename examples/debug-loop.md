# Example: the "run → read → fix" debug loop

> You: Test the game and fix the errors.

The agent:

1. `clear_output` — clean log
2. `play_solo` — starts Play Solo (F5)
3. waits ~5 seconds (client-side pause)
4. `get_output` (`limit: 100`) — reads errors and prints
5. `get_play_state` — confirms the test is running
6. Spots an error, e.g. `Workspace.Script:3: attempt to index nil`:
   - `read_script` (`Workspace.Script`)
   - `write_script` with the fix
7. `stop_playtest` → `play_solo` again → `get_output` — confirms it's clean
8. `stop_playtest`, reports back to the user

The agent does all of this by itself, no human in the loop — that's the point of `roblox-mcp`.
