# /cockpit-delete — Delete a Cockpit task

Remove a task from Cockpit. This is a hard delete — the row is removed from `cockpit.md`. There is no archive.

## Instructions

1. Parse the task number `N` from the user's input. If unclear, run `python3 /home/eyifrah/cockpit list` so the user can pick.
2. Confirm with the user before deleting unless the user clearly stated which one and used a destructive verb ("delete", "remove", "drop") — short list of what's about to be deleted (`#N: <task name>`), then ask for confirmation.
3. Run:
   ```
   python3 /home/eyifrah/cockpit delete <N>
   ```
4. Display the script's output as-is.

## Rules

- Never ask the user to run the command themselves — always run it directly.
- Deletion shifts the remaining task numbers down (e.g. deleting #2 makes the old #3 the new #2). Mention this if the user is about to do further edits.
