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

The engine injects a slide tracker into every served deck so that comments attach to the
slide they were written on. It finds the active slide by **position**: the 1-based index of
the element carrying `.active` among all `.slide` elements, falling back to the on-screen
slide and only then to a `slide-N` id.

The injection is done with:

```js
html = html.replace('</body>', injection + '</body>');
```

So the one hard requirement is:

- **The HTML must contain a literal `</body>`.** A fragment without it gets no tracker at
  all, the app never receives a `deckSlideChange`, and every comment silently files against
  slide 1.

Beyond that: each slide is an element with class `slide`, exactly one carries `active` at a
time, and slides sit in DOM order. `id="slide-N"` is useful for the nav snippet but is not
what comment tracking depends on.

Verify after publishing: read the deck back with the `get_deck` MCP tool and confirm the
stored HTML ends with `</body>`.

## Theme — Augury (single source of truth)

The deck's look comes entirely from the **`augury-deck-theme`** skill. Invoke it
and use its palette tokens, ready-to-paste CSS block, and component styles
verbatim — it owns every color, the card/formula/combo boxes, badges, table
headers, fonts, and the `→`/`·` bullet convention.

- Do not hardcode or invent colors — read them from `augury-deck-theme`.
- If that skill is unavailable, stop and tell the user to install the
  `augury-design` plugin (the theme lives there). Do not improvise a palette.
