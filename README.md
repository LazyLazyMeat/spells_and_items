# Spells and Items by LLM

Static web app for browsing D&D 5e spells and magic items.
Data is parsed from dnd.su HTML pages via PowerShell scripts.

## Structure

- `run.bat` — menu-driven entry point
- `scripts/spells/` — spell extraction / download / parsing
- `scripts/items/` — item extraction / download / parsing
- `scripts/common/` — web data builders + packer
- `web/` — static app (HTML/CSS/JS)
- `source/` — downloaded HTML (gitignored)
- `data/` — parsed JSON (gitignored)
- `dist/` — packaged zip (gitignored)

## Rebuild from scratch

1. Place `source/spells.html` and `source/items.html` (index pages from dnd.su)
2. Run `run.bat`
3. Choose `9` (full pipeline: extract → save → parse → build → pack)
4. Result: `dist/spells-and-items-web.zip`

## Individual steps

- `11`/`21` — extract links to index JSON
- `12`/`22` — download all item/spell pages
- `13`/`23` — parse pages to JSON
- `14`/`24` — build `web/spells.js` / `web/items.js`
- `8` — pack `web/` into zip
- `1`/`2` — save / parse a single page

## Notes

- `items-config.json` is UTF-8 with BOM (PowerShell 5.1 requirement).
- `.ps1` files are ASCII-only to avoid encoding issues.
- `web/spells.js` and `web/items.js` are generated, not versioned.