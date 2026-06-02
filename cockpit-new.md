# /cockpit-new — Create a new Cockpit task

Create a new task in Cockpit.

## Inputs

| Field    | Required | Default   | Notes |
|----------|----------|-----------|-------|
| task     | yes      | —         | Short task name |
| status   | no       | `ongoing` | Known: ongoing, done, blocked, in progress, paused, waiting |
| notes    | no       | `-`       | Free-form context |
| spec     | no       | `-`       | File path or URL only — never inline content |
| monday   | no       | `-`       | Monday item URL |
| date     | no       | today     | YYYY-MM-DD |

## Instructions

1. Parse as many fields as possible from the user's input.
2. If `task` cannot be determined, ask for it — do not invent one.
3. **Always ask for any of the following that were not provided: `notes`, `monday`.** Ask all at once in a single message. Accept "none" or "skip" as valid answers.
4. If the user mentions a Monday URL anywhere in their input, pull it into `--monday`.
5. Run:
   ```
   python3 /home/eyifrah/cockpit new \
     --task "<task>" \
     [--status "<status>"] \
     [--notes "<notes>"] \
     [--spec "<spec>"] \
     [--monday "<monday-url>"] \
     [--date "<YYYY-MM-DD>"]
   ```
   Only pass flags for fields that have real values (skip fields that are still `-`).
6. Display the script's output as-is.

## Rules

- Never ask the user to run the command themselves — always run it directly.
- Ask for missing fields in one shot, not sequentially.
- If the user provides a long block of text intended as a spec, ask whether to save it as a file and pass the path; the spec field is a reference only.
