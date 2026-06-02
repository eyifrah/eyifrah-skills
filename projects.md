# /projects — Personal Project List Manager

You are managing Elad's personal work log. This skill covers displaying, adding, and updating items in his project list, and syncing status to Monday.com.

## Work log location
`~/.claude/projects/-home-eyifrah/memory/work_log.md`

## Display the work log
Always run `python3 /home/eyifrah/worklog` to display it. Never ask the user to run it themselves.

## Adding a new item
When the user wants to add a new process or task:
1. If they mention a Monday.com item, find it:
   - First try searching by name on the relevant board
   - If they provide a board URL, extract the board ID and search there
2. Read the Monday item fully — always fetch both item details AND all updates/comments before reporting back
3. Append a new row to the work log markdown table:
   `| YYYY-MM-DD | Task name | Board / Area | status | Monday item: <url> |`
4. Run the worklog to confirm it looks right

## Updating an existing item
When the user provides a status update for a task:
1. Read all existing updates on the Monday item first (never post blind)
2. Post the update to Monday on the user's behalf with a clear, structured summary
3. Update the status in the work log if it changed
4. Provide the direct link to the new update: `https://augury.monday.com/boards/<board_id>/pulses/<item_id>/posts/<update_id>`

## Rules
- Always read existing Monday updates before posting a new one
- Never ask the user to run a command — run it yourself
- When displaying the log, just run the script — don't re-render it manually in text
- Status values: `ongoing`, `done`, `blocked`, `in progress`, `paused`
- Keep notes concise; Monday URL goes in the Notes field
