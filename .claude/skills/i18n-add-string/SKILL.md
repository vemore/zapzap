---
name: i18n-add-string
description: Add, rename or remove a user-facing string of the ZapZap Flutter client (frontend-flutter/) across its ten ARB files — French template, English, and es, pt, de, ru, ja, hi, id, ar — with the game-terms glossary, ICU plurals per language, Arabic right to left, gen-l10n, and the bulk procedure (one agent per locale) for many keys or long text such as the rules sheet or the tutorial. Use whenever new text must appear in the Flutter UI, a label is reworded, a hardcoded string is found in a widget, or a plural or parameterised message is added. Triggers: "add a string", "ajouter une traduction", "nouveau texte", "translate this label", "hardcoded string", "plural form", "gen-l10n", "ARB", "traduire les langues".
---

# Adding a localized string to the Flutter client

Ten ARB files stay in lockstep: **the same key set in each**, every value translated. A key
missing from one file fails `test/l10n_locales_test.dart`; a value left in English fails
nothing — `scripts/arb_keys.py --values` is what catches it. Background: `.llmwiki/FlutterI18n.md`.

## Layout

| Fact | Value |
|---|---|
| ARB files | `frontend-flutter/lib/l10n/app_{fr,en,es,pt,de,ru,ja,hi,id,ar}.arb` |
| **Template** | `app_fr.arb` — French, written by hand, the only file with `@key` metadata |
| English | `app_en.arb` — written by hand too; the eight others are translated from both |
| Game terms | `frontend-flutter/lib/l10n/GLOSSARY.md` — one term per concept and language |
| Generated | `lib/l10n/app_localizations*.dart` — **not committed**, `flutter gen-l10n` writes them |
| Config | `frontend-flutter/l10n.yaml` (`nullable-getter: false`) |
| Supported locales | `AppLocalizations.supportedLocales`, generated from the ARB files; `resolveLocale` (`lib/app.dart`) falls back to `fr` |

## Procedure

### 1. French first, then English, then the eight

`app_fr.arb` gets the key **and** its `@key` block (a description; placeholders with their
type). The French client says **"tu"**, never "vous" (`test/l10n_test.dart` refuses it).

```json
"partyLeft": "Tu as quitté la partie",
"@partyLeft": {
  "description": "Snackbar after the player leaves a party"
},
```

`app_en.arb` and the eight translated files get the bare key and value — no `@key` block.

- **Take every game term from `GLOSSARY.md`**, in that language's column: deck, discard
  pile, draw, take, round, hand, run, counteracted, eliminated… The same concept uses the
  same word on every screen. A term missing there is added there first, then used.
- `ZapZap` and `Golden Score` stay in Latin script in every language.
- Arabic (`ar`) is right to left: `MaterialApp` mirrors the layout from the locale; a string
  must not rely on left-to-right order (a leading arrow, "left"/"right" wording).
- A handful of short strings you translate yourself; many keys or long text: §1b.

### 1b. Bulk translation — one agent per locale

Many keys at once, or long-form text (the rules sheet's `rules*` strings, the tutorial):

1. **The orchestrator — the top-level session — writes the French master** in `app_fr.arb`,
   and `app_en.arb`: they are the reference every locale is checked against, never
   delegated.
2. **It launches one agent per remaining locale — `es`, `pt`, `de`, `ru`, `ja`, `hi`, `id`,
   `ar` — all eight in one message**, no `isolation`: each edits **only its own file**, by
   absolute path in the worktree, and does not commit.
3. Every agent gets **the same brief**: the new keys with their French and English values;
   keys, placeholder names and ICU syntax copied byte for byte; that locale's plural
   categories (§3); its `GLOSSARY.md` column and its form of address (the glossary's last
   row); `ZapZap`, `Golden Score` and card symbols (♠ ♥ ♣ ♦) as the master has them;
   numbers unchanged; the rest of the file untouched.
4. **It reviews what comes back** — `python3 scripts/arb_keys.py`, placeholders, plural
   categories, glossary terms — then runs §4 and §6 and commits once.

The orchestrator, because a subagent cannot launch agents of its own. An implementing agent
(`ship-parallel`) that meets bulk translation writes the French and English, stops before
its commit, names the locales left, and the orchestrator finishes them in that worktree.

### 2. Placeholders

```json
"createPartySlotBotUnavailable": "Bot — {difficulty} (aucun disponible)",
"@createPartySlotBotUnavailable": {
  "description": "Seat option disabled because every bot of that difficulty is already seated",
  "placeholders": { "difficulty": { "type": "String" } }
}
```

Placeholder **names** are identical in all ten files; the text around them is translated and
the placeholder may move. `l10n_locales_test.dart` checks each file keeps the English
message's placeholders.

### 3. Plurals — ICU, never hand-rolled

`'$n carte${n > 1 ? "s" : ""}'` is a defect. Use ICU, as `lobbySeatsChip` does:

```json
"lobbySeatsChip": "{count, plural, =1{1 place} other{{count} places}}",
```

Each translated file uses exactly its language's CLDR categories
(`pluralCategories` in `test/l10n_locales_test.dart`), always with `other`:

| Languages | Categories |
|---|---|
| `ja`, `id` | `other` |
| `fr`, `en`, `es`, `pt`, `de`, `hi` | `one`, `other` (`=1` may stand for `one`) |
| `ru` | `one`, `few`, `many`, `other` (`=1` is **not** enough: 21, 31… are `one`) |
| `ar` | `zero`, `one`, `two`, `few`, `many`, `other` (`=0`, `=1`, `=2` may stand for them) |

Never write an explicit case and its category together (`=1` and `one`): gen-l10n keeps one
of them and drops the other; the test refuses it.

### 4. Regenerate

```bash
cd frontend-flutter && flutter gen-l10n
```

The generated files are gitignored: regenerate after every ARB change, `flutter analyze`
does not.

### 5. Use it

```dart
import '../l10n/app_localizations.dart';
// in build():
final l10n = AppLocalizations.of(context);   // non-null: nullable-getter: false
Text(l10n.partyLeft)
Text(l10n.createPartySlotBotUnavailable(label))
Text(l10n.lobbySeatsChip(3))
```

### 6. Verify

```bash
python3 scripts/arb_keys.py          # keys against app_fr.arb, values against app_en.arb
cd frontend-flutter && flutter analyze && flutter test test/l10n_test.dart test/l10n_locales_test.dart
```

`scripts/arb_keys.py` (`--keys`, `--values` or `--unused` alone) is a report, not a gate:

- **keys** — every template key is in all ten files, and no file has a key the template
  lacks (the Flutter test says the same, slower).
- **values** — no non-English file still holds the literal `app_en.arb` string. A value
  with no letter outside its placeholders (`{wins} / {games}`) is never reported.

Your new keys must not appear in the `--values` output. When a translation legitimately
equals English — a brand, a bot's name, a loanword ("Tutorial" in German) — add the key to
`SAME_AS_ENGLISH_OK` in `scripts/arb_keys.py` with a comment saying why, rather than
distorting the translation. A key ending in `*` exempts its camelCase family. Values found
on keys you did not touch are a `wip/` entry, not a fix in your change.

## Rules

- No user-facing string literal outside `lib/l10n/`: `Text('Bonjour')` is a defect.
- Never translate user content: usernames, party names, scores.
- Renaming a key: all ten files plus every call site. Removing one: all ten plus the `@key`
  block; after removing a screen, `python3 scripts/arb_keys.py --unused` lists the keys no
  `.dart` file under `lib/` reads any more.
- A term changed in `GLOSSARY.md` changes in its whole ARB file, in the same change.
- Translated ARB files do not count in a pull request's size (`ship-parallel` §3, step 1).

## Adding a language

1. Copy `app_en.arb` to `lib/l10n/app_XX.arb` (`"@@locale": "XX"`), translate every value,
   and add a column to `GLOSSARY.md`.
2. Add the locale to `translated`, `pluralCategories` and `exactCategories` in
   `test/l10n_locales_test.dart`, and a device locale to its `resolveLocale` case.
3. `flutter gen-l10n` — `supportedLocales` follows the ARB files — then the board's
   overflow tests at 360×740 in the new language.

## Not ported (yet)

countscore pairs its `arb_keys.py` with a PostToolUse hook (progress after each ARB edit)
and a commit-time refusal of a missing key or an English value. ZapZap has neither: a
possible later step, once the `--values` report is clean.
