# /deck — Build a presentation deck

Turn context, content, and source material into a polished HTML deck.

## Flow

### Phase 1 — Gather & Build Markdown
1. Accept any combination of: free text, URLs, Slack links, Google Docs, or existing notes as input.
2. Propose a slide structure (title + one-line summary per slide). Confirm with user before writing content.
3. Write the markdown deck — one `## Slide N — Title` section per slide, separated by `---`.
4. Iterate slide by slide with the user until the markdown is agreed.

### Phase 2 — Convert to HTML
5. Once markdown is signed off, convert to an HTML deck styled with the **Augury theme** (see Theme below).
6. Save both files to `~/cockpit-data/specs/<deck-name>.md` and `~/cockpit-data/specs/<deck-name>.html`.
7. Honour the **slide markup contract** below — without it the engine's per-slide comments break.

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
- Never open the HTML in Chrome and never hand the user a local `.html` path. The Deck Engine URL is the only deliverable; the HTML file is just the publish payload.
- Slides are separated by `---` in markdown. Slide heading format: `## Slide N — Title`.
- Ask for the deck name (used for filenames) if not obvious from context.
- Always push to the Deck Engine after finalising — keep engine in sync.
- The `<!-- deck-engine-id: -->` comment goes on line 1 of both the `.md` and `.html` files.

## Slide markup contract (required for engine features)

The engine tracks the active slide so comments attach to the slide they were written on.
It injects a tracker into every served deck that does this:

```js
var el = document.querySelector('.slide.active');
return parseInt(el.id.replace('slide-','')) || 1;
```

and it injects that script with `html.replace('</body>', …)`.

So the HTML **must** satisfy both of these, or every comment silently files against slide 1:

- Each slide carries `id="slide-N"`, 1-based and matching its position, alongside `class="slide"`. The visible one also has `active`; navigation toggles `active`.
- The file contains a literal `</body>`. A fragment with no `</body>` gets no tracker injected at all.

Verify after publishing: the stored HTML should have one `id="slide-N"` per slide and a `</body>`. Read it back with the `get_deck` MCP tool.

## Theme — Augury (single source of truth)

The deck's look comes entirely from the **`augury-deck-theme`** skill. Invoke it
and use its palette tokens, ready-to-paste CSS block, and component styles
verbatim — it owns every color, the card/formula/combo boxes, badges, table
headers, fonts, and the `→`/`·` bullet convention.

- Do not hardcode or invent colors — read them from `augury-deck-theme`.
- If that skill is unavailable, stop and tell the user to install the
  `augury-design` plugin (the theme lives there). Do not improvise a palette.
