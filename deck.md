# /deck — Build a presentation deck

Turn context, content, and source material into a polished HTML deck.

## Flow

### Phase 1 — Gather & Build Markdown
1. Accept any combination of: free text, URLs, Slack links, Google Docs, or existing notes as input.
2. Propose a slide structure (title + one-line summary per slide). Confirm with user before writing content.
3. Write the markdown deck — one `## Slide N — Title` section per slide, separated by `---`.
4. Iterate slide by slide with the user until the markdown is agreed.

### Phase 2 — Convert to HTML
5. Once markdown is signed off, convert to an HTML deck using the Augury dark theme (see Style Guide below).
6. Save both files to `~/cockpit-data/specs/<deck-name>.md` and `~/cockpit-data/specs/<deck-name>.html`.
7. Open the HTML in Chrome: `google-chrome <path> &`

### Phase 3 — HTML Iteration
8. Continue iterating on content or style as requested.
9. **Every change must be applied to both the markdown and HTML.** They must never diverge.

### Phase 4 — Publish to Deck Engine
10. After the HTML is finalised (new deck or updated), push to the Deck Engine:

**Config:** read `~/.cockpit/deck-engine.json` for `baseUrl`, `apiKey`, `userEmail`, and `userName`.

**New deck** (no engine ID yet):
```bash
RESULT=$(curl -s -X POST "<baseUrl>/api/decks" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <apiKey>" \
  -d "{\"title\": \"<title>\", \"authorEmail\": \"<userEmail>\", \"authorName\": \"<userName>\", \"html\": $(cat <html-path> | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}")
echo $RESULT  # extract id
```
Store the returned `id` as a `<!-- deck-engine-id: <id> -->` comment at the top of the HTML file and the markdown file.

**Existing deck** (has engine ID — read it from the `<!-- deck-engine-id: -->` comment):
```bash
curl -s -X PUT "<baseUrl>/api/decks/<id>" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <apiKey>" \
  -d "{\"html\": $(cat <html-path> | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}"
```

11. Return the deck URL: `<baseUrl>/app#deck/<id>`

## Rules

- Never let markdown and HTML diverge — every edit touches both files.
- Never show the raw HTML to the user — it's too noisy. Show the markdown for content review.
- Always open Chrome after generating or significantly updating the HTML.
- Slides are separated by `---` in markdown. Slide heading format: `## Slide N — Title`.
- Ask for the deck name (used for filenames) if not obvious from context.
- Always push to the Deck Engine after finalising — keep engine in sync.
- The `<!-- deck-engine-id: -->` comment goes on line 1 of both the `.md` and `.html` files.

## Style Guide — Augury Dark Theme

```
Background:    #0f1117
Card:          #1a1d27  border: 1px solid #2a2d3a  border-radius: 12px
Accent blue:   #5b6aff  (slide labels, dots, formula borders, → bullets)
Accent purple: #a370f7  (All Communications / combo boxes)
Text primary:  #ffffff / #e8eaf0
Text secondary:#b0b8cc
Text muted:    #666e88 / #555c75
Table header:  #22263a
Formula box:   background #12141e, left border 3px #5b6aff, monospace, color #a0c4ff
Combo box:     background #1e1a2e, left border 3px #a370f7, color #c4b0e8
Badges:        green (#1a3a2a / #4caf80), yellow (#3a2e1a / #e0a040)
Navigation:    prev/next buttons + dot indicators + keyboard arrow support
Font:          -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif
```

Slide label (top of each slide): small caps, #5b6aff, shows the deck title.
Bullet lists use `→` in #5b6aff instead of default bullets.
Sub-lists use `·` in #5b6aff.
