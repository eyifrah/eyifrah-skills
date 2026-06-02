# /cockpit-edit — Edit a Cockpit task

Update one or more fields of an existing Cockpit task. Optionally posts a Monday update when the status changes on a linked task.

## Inputs

The user identifies the task by number (`#N`) and describes the changes. Parse into:

| Field   | Notes |
|---------|-------|
| task    | Rename |
| area    | |
| status  | ongoing, done, blocked, in progress, paused, waiting |
| notes   | Replaces existing notes |
| spec    | File path or URL only |
| monday  | Monday item URL |
| date    | YYYY-MM-DD |

## Instructions

1. If the task number is unclear, run `python3 /home/eyifrah/cockpit list` first so the user can pick.
2. **Capture the old state** before editing — especially the current `status` and `monday` URL if a status change is requested. The simplest way is to run `python3 /home/eyifrah/cockpit list` and read the row.
3. Run:
   ```
   python3 /home/eyifrah/cockpit edit <N> \
     [--task "<task>"] \
     [--area "<area>"] \
     [--status "<status>"] \
     [--notes "<notes>"] \
     [--spec "<spec>"] \
     [--monday "<monday-url>"] \
     [--date "<YYYY-MM-DD>"]
   ```
   Pass only the flags the user wants to change. Unspecified fields are preserved.
4. Display the script's output as-is.
5. **Auto-post Monday update** if both:
   - `--status` was changed (new value differs from old), AND
   - The task has a Monday URL (either pre-existing or set in this same edit)

   Extract the Monday item ID from the URL (`/pulses/<itemId>`). Then call the Monday `create_update` MCP tool with a short HTML body explaining the change, e.g.:
   ```
   <p>Status changed: <b>&lt;old&gt;</b> → <b>&lt;new&gt;</b>. &lt;optional one-line reason from notes if user provided one&gt;</p>
   ```
   Return the direct link to the update: `https://augury.monday.com/boards/<boardId>/pulses/<itemId>/posts/<updateId>` (per the feedback memory on Monday update links).

## Rules

- Never ask the user to run the command themselves — always run it directly.
- Notes/spec edits replace the existing value; if the user says "add to notes", read the current value and pass the combined text.
- Pipe characters (`|`) in inputs will be replaced with `/` by the script — warn the user if their input contains one.
- If the user explicitly says "don't update Monday" or similar, skip the auto-post step.
