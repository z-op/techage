# Agent instructions — Techage Russian translation

This file documents work done by an automated agent (AtomCode) on the
`localisation_ru` branch of the Techage Minetest mod repository.

## Scope of work

### 1. Locale (`locale/techage.ru.tr`)
- Filled in ~20 empty translations (items, display settings, error messages)
- Added ~43 new translation keys for ICTA and Lua controller in-game help tabs
- All keys now have non-empty Russian values

### 2. In-game help — ICTA controller (`icta_controller/formspec.lua`)
- sHELP rewritten from a single multiline `[[...]]` block into individual
  `S()` calls (~30 short translatable strings)
- GitHub links changed from German to English
- Added `local S = techage.S`

### 3. In-game help — Lua controller (`lua_controller/controller.lua`)
- sHELP rewritten from `[[...]]` to individual `techage.S()` calls
- Uses `techage.S` directly because `S` is already defined as a
  pos-to-string helper

### 4. Manuals (`manuals/manual_ta3_RU.md`)
- Added missing sections: **TA3 CRT монитор** and **TA3 Смотровое окно**
  (translated from English)

### 5. Manuals (`manuals/manual_ta4_RU.md`)
- Created new `## TA4 Дисплеи` section with general description
- Moved `### TA4 Дисплей` and `### TA4 Дисплей XL` from ICTA Controller
  section into the new Displays section
- Added missing `### TA4 Дисплей II` and `### TA4 Дисплей II XXL`
- Fixed German PDF link → English markdown link in
  `manuals/ta4_icta_controller_RU.md`

### 6. In-game documentation (`doc/manual_ta3_RU.lua`)
- Added CRT Monitor and Observation Window title + text entries
- Now has 88 titles (matching English version)

### 7. In-game documentation (`doc/manual_ta4_RU.lua`)
- Added TA4 Displays section header and Display II / Display II XXL
  title + text entries
- Now has 97 titles (was 94; EN has 98 — the remaining difference
  is the deprecated Move Controller, intentionally omitted)

### 8. Fixes applied during review
- "Дисплеи могут **использовать**" → "Дисплеи могут **использоваться**"
  (missing reflexive suffix)

## Commit style

Use English commit messages. Example:
```
fix(ru): add missing CRT Monitor and Observation Window sections
```

## Branch

Branch: `localisation_ru`
Remote: `git@github.com:z-op/techage.git`

## i18n.py — locale template sync

The repository root contains `i18n.py`, a Minetest i18n tool that scans all
`.lua` files for `S()` calls and regenerates `locale/template.txt` and all
`locale/*.tr` translation files accordingly.

### When to run

Run `python3 i18n.py` from the repo root **after any of these changes**:

1. Adding, modifying, or removing `S("...")` calls in any `.lua` file
   (this includes the ICTA formspec help and Lua controller help).
2. Adding or removing translatable strings in Lua source files.
3. Before committing locale changes, to ensure `template.txt` matches
   the actual source strings.

### What it does

- Scans all `.lua` files for `S("string")` — including any new strings
  added by code changes.
- Regenerates `locale/template.txt` with all found strings + source file
  comments.
- Updates each `locale/*.tr` file: adds new keys, preserves existing
  translations, and (unless `--truncate-unused` is passed) keeps orphaned
  translations marked with a comment header.
- Creates `*.old` backup files when `--old-file` is passed.

### Typical usage

```bash
cd /path/to/techage
python3 i18n.py --verbose --old-file
```

The `--old-file` flag creates `.tr.old` backups. The `--verbose` flag
shows which files are scanned and how many strings are found in each.

## markdown_to_lua.py — in-game manual regeneration

The `manuals/markdown_to_lua.py` script generates `doc/manual_*.lua` files
from the corresponding `manuals/manual_*.md` markdown files. It uses
`mistune==0.8.4` for Markdown parsing.

### When to run

Run `python3 manuals/markdown_to_lua.py` from the repo root **after**:

1. Adding, removing, or editing sections in any `manuals/manual_*.md` file.
2. Creating a new language manual (e.g. `manual_XX.md`).

### What it does

- Regenerates ALL `doc/manual_*.lua` files from their markdown sources.
- Preserves the same structure (titles, texts, images, plans).
- The script has all file mappings hardcoded at the bottom.

### Typical usage

```bash
cd /path/to/techage
python3 manuals/markdown_to_lua.py
```

Run it BEFORE running `i18n.py`, because the doc Lua files may contain
`S()` calls that need to be picked up by the i18n template scanner.
