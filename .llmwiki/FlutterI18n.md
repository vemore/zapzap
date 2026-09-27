# FlutterI18n

> Scope: the Flutter client's localisation: the ten ARB files, the glossary, the l10n tests,
> generated code, and the "tu" voice.
> Related: [[FrontendFlutter]] · [[FlutterParties]] · [[FlutterGameBoard]]
> Updated: 2026-09-27

## Facts

### Localisation

- `frontend-flutter/l10n.yaml`: `arb-dir: lib/l10n`, template `app_fr.arb`,
  `nullable-getter: false`. French is the default: `resolveLocale` (`app.dart`) picks the
  device's language, whatever its region, when it is one of the ten, else `fr`.
- **Ten languages (2026-09-26)**: French and English, written by hand, and the eight most
  used on the Play Store, translated from both by one Haiku agent per language: Spanish
  (`es`), Portuguese (`pt`, Brazilian — one file for `pt_BR` and `pt_PT`), German (`de`),
  Russian (`ru`), Japanese (`ja`), Hindi (`hi`), Indonesian (`id`), Arabic (`ar`, right to
  left: `MaterialApp` mirrors the layout from the locale). The translated files carry no
  `@key` metadata: the template's is enough for gen-l10n. A new key goes into all ten
  files; the eight can be regenerated the same way. `ZapZap` and `Golden Score` are left
  untranslated.
- **One glossary of game terms, `frontend-flutter/lib/l10n/GLOSSARY.md`** (2026-09-27): a
  table with a column per language — deck, discard pile, the "À prendre ensuite" and
  "Posées" labels, draw, take, call ZapZap, counteracted, round, hand, eliminated, run… Every
  translated file uses its column on every screen; a new string or language takes its terms
  from there, and a term changed there changes in its whole file. The eight files had one
  review pass against it (a stronger model, not yet fluent speakers: the pull request
  `chore/flutter-l10n-review` lists the terms held least certain).
- `test/l10n_locales_test.dart`: each translated file has exactly the keys of `app_fr.arb`,
  the placeholders of the English message (a small ICU parser), the CLDR plural categories
  of its language (`ru` one/few/many/other, `ar` zero/one/two/few/many/other, `ja`/`id`
  other) and an `other` in every plural and select; `resolveLocale` on regional device
  locales; the home screen in each language (`ar` right to left); the game board's play,
  draw and hand-size phases at 360×740, text scales 1.0 and 1.5, in each language, without
  overflow.
- **Translated ARB files are not counted in a pull request's size** (`ship-parallel` §3.1:
  every `lib/l10n/app_*.arb` but `app_fr.arb` and `app_en.arb`).
- **No user-facing string literal outside `lib/l10n/`**: every text goes through
  `AppLocalizations.of(context)`. The React client mixes French and English; the port
  unifies them in the ARB files.
- The generated `lib/l10n/app_localizations*.dart` are **not committed**
  (`frontend-flutter/.gitignore`): `flutter gen-l10n` writes them. A `flutter pub get`
  sometimes does too, but not reliably (not when it finds nothing to resolve), and `flutter
  analyze` never does (checked 2026-09-22): after an ARB change, run `gen-l10n`. CI, the
  commit gate and `worktree_setup.sh` run it explicitly. Keeps parallel pull requests that
  each add strings free of conflicts in generated code.
- `test/l10n_test.dart` fails when a key is in one ARB file and not the other, and when
  a French message says "vous" (`vousMarkers`: vous, votre, vos, êtes, faites, dites and
  any word ending in "-ez", but not "rendez-vous", "chez", "nez", "assez").
- **The French client says "tu"** to the player, everywhere: "Toi", "à toi de choisir",
  "Choisis…", "Ce n'est pas ton tour.", "Réessaie.".

## Decisions & History

- **Eight more languages (2026-09-26, `feat/flutter-l10n-top-languages`).** Ahead of the Play
  Store release: es, pt (Brazilian), de, ru, ja, hi, id, ar, translated by Haiku agents from
  the English and French files, then checked by `test/l10n_locales_test.dart`.
- **Tutoiement everywhere (2026-09-23, `chore/flutter-tu-voice`).** The user chose "tu",
  as in the UX study, over the "vous" the first screens used: on the board, the "Vous"
  badge sat next to "Ton tour". Twenty French strings changed wording only, no key was
  renamed, and English is unchanged. `test/l10n_test.dart` keeps "vous" out of
  `app_fr.arb`.
- **Generated l10n not committed (2026-09-22)**, unlike countscore: several Flutter pull
  requests will add strings in parallel, and generated files would conflict on every one.
