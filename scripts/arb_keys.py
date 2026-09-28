#!/usr/bin/env python3
"""Check the Flutter ARB files against the template (keys) and against English (values).

    python3 scripts/arb_keys.py            # both checks
    python3 scripts/arb_keys.py --keys     # key sets only
    python3 scripts/arb_keys.py --values   # values still identical to app_en.arb only
    python3 scripts/arb_keys.py --unused   # template keys no .dart file under lib/ reads

Ten ARB files under frontend-flutter/lib/l10n/ must hold the same keys: a key missing
from one language is a silent fallback for those players. The template is app_fr.arb,
read from frontend-flutter/l10n.yaml so the two cannot drift. Metadata ("@key",
"@@locale") is left out; key order differs between files, so sets are compared.

Counting keys is not enough: a key can be present in all ten files and still hold the
literal English string in some of them (wip 2026-09-26-flutter-l10n-translations-
unreviewed). --values compares every non-English locale against app_en.arb, minus the
matches that are legitimate (SAME_AS_ENGLISH_OK).

test/l10n_locales_test.dart already fails on a missing key, a placeholder or a plural
category; this script adds the value check, and answers in a second without Flutter.
It is a report the i18n-add-string skill runs, not a commit gate. Ported from
countscore's .claude/hooks/arb_keys.py.

Exit codes: 0 in sync, 1 divergent, 3 the l10n setup could not be read (l10n.yaml, or
invalid JSON in an ARB file).
"""

import argparse
import json
import os
import pathlib
import re
import sys

# The Flutter project: frontend-flutter/ next to this script's directory, or
# ARB_KEYS_PROJECT (the tests point it at a fixture).
PROJECT = pathlib.Path(
    os.environ.get("ARB_KEYS_PROJECT", pathlib.Path(__file__).resolve().parent.parent / "frontend-flutter")
)

# The English file: an untranslated value looks like it, since the eight other
# languages were translated from it (and from the French template).
ENGLISH = "en"

ALL_LOCALES = "*"

# Keys whose value is legitimately identical to English. A key maps to ALL_LOCALES or
# to the set of locales where the match is deliberate; a key ending in "*" exempts the
# camelCase family under that prefix (not the bare prefix). EXTENDING THIS LIST IS THE
# ESCAPE HATCH: when a genuine translation equals the English string, add it here with
# a comment saying why, rather than distorting the translation.
#
# A value with no letter outside its {placeholders} ("#", "{wins} / {games}") is never
# reported: there is nothing to translate (has_words).
#
# Measured on the ten files on 2026-09-27. What the list leaves reported is doubtful
# rather than wrong -- a fluent speaker decides (wip 2026-09-26-flutter-l10n-translations-
# unreviewed).
SAME_AS_ENGLISH_OK = {
    # Brand and mode names, Latin script everywhere (lib/l10n/GLOSSARY.md).
    "appTitle": ALL_LOCALES,  # "ZapZap"
    "gameZapZapBadge": ALL_LOCALES,  # "ZapZap"
    "gameZapZapButton": ALL_LOCALES,  # "ZapZap!"
    "rulesZapZapTitle": ALL_LOCALES,  # "ZapZap"
    "standingsZapzaps": ALL_LOCALES,  # "{successful}/{total} ZapZap"
    "goldenScore": ALL_LOCALES,  # "Golden Score"
    "rulesGoldenScoreTitle": ALL_LOCALES,  # "Golden Score"
    # Bot names and the technology they name.
    "botDifficultyThibot": ALL_LOCALES,  # "Thibot", a bot's name
    "difficultyThibot": ALL_LOCALES,
    "botDifficultyLlm": ALL_LOCALES,  # "LLM (Llama 3.3)"
    "difficultyLlm": ALL_LOCALES,
    "difficultyMl": ALL_LOCALES,  # "ML (TensorFlow)"
    # French, written by hand: the same word in both languages.
    "adminTitle": {"fr"},  # "Administration"
    "points": {"fr"},  # "{score} pts"
    "historyWinnerWithScore": {"fr"},  # "{username} ({score} pts)"
    # Loanwords and words spelt the same.
    "adminUserAdminBadge": {"fr", "de", "es", "pt", "id"},  # "Admin"
    "botTotalBots": {"fr", "de", "es", "pt"},  # "Bots"
    "botCount": {"fr", "es", "pt"},  # "{count} bot(s)"
    "createPartySlotBot": {"fr", "de", "es", "pt", "id"},  # "Bot — {difficulty}"
    "gameRoundEndColumnTotal": {"fr", "es", "pt", "id"},  # "Total"
    "menuTutorial": {"de", "es", "pt", "id"},  # "Tutorial"
    "tutorialTitle": {"de", "es", "pt", "id"},  # "Tutorial"
    "partyStatusLabel": {"de", "pt", "id"},  # "Status"
    "gameRoundOverHandLabel": {"de"},  # "Hand", the glossary's German term
    # SI unit symbols, written the same in Latin-script languages.
    "turnTimerSeconds": {"fr", "de", "es", "pt"},  # "{seconds} s"
    "turnTimerMinutes": {"fr", "de", "es", "pt"},  # "{minutes} min"
}

_EXEMPT_PREFIXES = {k[:-1]: v for k, v in SAME_AS_ENGLISH_OK.items() if k.endswith("*")}


def is_exempt(key, locale):
    """True when key holding the English string in locale is deliberate."""
    candidates = [SAME_AS_ENGLISH_OK.get(key)]
    candidates += [
        v
        for prefix, v in _EXEMPT_PREFIXES.items()
        if key.startswith(prefix) and key[len(prefix) :][:1].isupper()
    ]
    return any(c == ALL_LOCALES or (c is not None and locale in c) for c in candidates)


def has_words(value):
    """True when value holds a letter outside its plain {placeholders}."""
    return any(c.isalpha() for c in re.sub(r"\{\w+\}", "", value))


def messages(path):
    with path.open(encoding="utf-8") as handle:
        return {k: v for k, v in json.load(handle).items() if not k.startswith("@")}


def check_keys(template_locale, loaded):
    """Report keys present in the template but not in a locale, and vice versa."""
    reference = set(loaded[template_locale])
    lines = []
    for locale, values in sorted(loaded.items()):
        keys = set(values)
        if reference - keys:
            lines.append(f"l10n: {locale} lacks {len(reference - keys)} key(s): {', '.join(sorted(reference - keys))}")
        if keys - reference:
            lines.append(f"l10n: {locale} has key(s) the template lacks: {', '.join(sorted(keys - reference))}")
    return lines


def check_values(loaded):
    """Report, per locale, the values still identical to English outside the exemptions."""
    english = loaded.get(ENGLISH)
    if english is None:
        return []
    lines = []
    for locale, values in sorted(loaded.items()):
        if locale == ENGLISH:
            continue
        same = sorted(
            k for k, v in english.items() if values.get(k) == v and has_words(v) and not is_exempt(k, locale)
        )
        if same:
            lines.append(f"l10n: {locale} holds the English string for {len(same)} key(s): {', '.join(same)}")
    return lines


def check_unused(directory, reference):
    """Report template keys no .dart file under lib/ mentions as a whole word.

    The generated app_localizations*.dart declare every key and are skipped. A false
    positive is a key built dynamically, never one read directly.
    """
    generated = {p.resolve() for p in directory.glob("app_localizations*.dart")}
    words = set()
    for path in (PROJECT / "lib").rglob("*.dart"):
        if path.resolve() not in generated:
            words.update(re.findall(r"\b\w+\b", path.read_text(encoding="utf-8")))
    unused = sorted(reference - words)
    if not unused:
        return []
    return [f"l10n: {len(unused)} template key(s) read by no .dart file under lib/: {', '.join(unused)}"]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--keys", action="store_true", help="only compare key sets with the template")
    mode.add_argument("--values", action="store_true", help="only list values identical to app_en.arb")
    mode.add_argument("--unused", action="store_true", help="only list template keys no .dart file reads")
    args = parser.parse_args()
    want_keys = args.keys or not (args.values or args.unused)
    want_values = args.values or not (args.keys or args.unused)

    try:
        config = (PROJECT / "l10n.yaml").read_text(encoding="utf-8")
        arb_dir = re.search(r"^arb-dir:\s*(\S+)", config, re.M).group(1)
        template_name = re.search(r"^template-arb-file:\s*(\S+)", config, re.M).group(1)
    except (OSError, AttributeError):
        print(f"l10n: could not read arb-dir/template-arb-file from {PROJECT / 'l10n.yaml'}", file=sys.stderr)
        return 3

    directory = PROJECT / arb_dir
    loaded, broken = {}, False
    for path in sorted(directory.glob("app_*.arb")):
        try:
            loaded[path.stem.removeprefix("app_")] = messages(path)
        except (OSError, json.JSONDecodeError) as error:
            print(f"l10n: invalid JSON in {path.name}: {error}", file=sys.stderr)
            broken = True
    template_locale = pathlib.Path(template_name).stem.removeprefix("app_")
    if broken or template_locale not in loaded:
        if template_locale not in loaded:
            print(f"l10n: template {template_name} not found in {directory}", file=sys.stderr)
        return 3

    lines = []
    if want_keys:
        lines += check_keys(template_locale, loaded)
    if want_values:
        lines += check_values(loaded)
    if args.unused:
        lines += check_unused(directory, set(loaded[template_locale]))

    for line in lines:
        print(line)
    return 1 if lines else 0


if __name__ == "__main__":
    sys.exit(main())
