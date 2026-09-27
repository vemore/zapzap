"""Tests for arb_keys.py on a fixture Flutter project -- no Flutter needed.

    uv run --no-project --with pytest pytest scripts/test_arb_keys.py
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().with_name("arb_keys.py")

FR = {
    "@@locale": "fr",
    "hello": "Bonjour",
    "@hello": {"description": "A greeting"},
    "score": "{wins} / {games}",
    "appTitle": "ZapZap",
    "family": "Famille",
    "familyTutorial": "Tutoriel",
}
EN = {"@@locale": "en", "hello": "Hello", "score": "{wins} / {games}", "appTitle": "ZapZap",
      "family": "Family", "familyTutorial": "Tutorial"}
DE = {"@@locale": "de", "hello": "Hallo", "score": "{wins} / {games}", "appTitle": "ZapZap",
      "family": "Familie", "familyTutorial": "Tutorial"}


def project(tmp: Path, **files: dict) -> Path:
    (tmp / "lib" / "l10n").mkdir(parents=True)
    (tmp / "l10n.yaml").write_text("arb-dir: lib/l10n\ntemplate-arb-file: app_fr.arb\n")
    for locale, content in {"fr": FR, "en": EN, "de": DE, **files}.items():
        text = content if isinstance(content, str) else json.dumps(content)
        (tmp / "lib" / "l10n" / f"app_{locale}.arb").write_text(text, encoding="utf-8")
    return tmp


def run(root: Path, *args: str) -> subprocess.CompletedProcess:
    env = {**os.environ, "ARB_KEYS_PROJECT": str(root)}
    return subprocess.run([sys.executable, str(SCRIPT), *args], env=env, capture_output=True, text=True)


sys.path.insert(0, str(SCRIPT.parent))
import arb_keys  # noqa: E402

sys.path.pop(0)


def test_is_exempt_and_has_words():
    assert arb_keys.is_exempt("appTitle", "ja")
    assert arb_keys.is_exempt("gameRoundOverHandLabel", "de")
    assert not arb_keys.is_exempt("gameRoundOverHandLabel", "pt")
    assert not arb_keys.is_exempt("family", "de")
    assert not arb_keys.has_words("{wins} / {games}")
    assert not arb_keys.has_words("#")
    assert arb_keys.has_words("{score} pts")


def test_prefix_exemption_covers_the_family_not_the_bare_prefix(monkeypatch):
    monkeypatch.setattr(arb_keys, "_EXEMPT_PREFIXES", {"family": {"de"}})
    assert arb_keys.is_exempt("familyTutorial", "de")
    assert not arb_keys.is_exempt("family", "de")
    assert not arb_keys.is_exempt("familyTutorial", "pt")


def test_in_sync_exits_zero(tmp_path):
    root = project(tmp_path, de={**DE, "familyTutorial": "Anleitung"})
    result = run(root)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout == ""


def test_value_identical_to_english_is_reported(tmp_path):
    result = run(project(tmp_path), "--values")
    assert result.returncode == 1
    assert "de holds the English string for 1 key(s): familyTutorial" in result.stdout


def test_placeholder_only_and_brand_values_are_not_reported(tmp_path):
    root = project(tmp_path, de={**DE, "familyTutorial": "Anleitung"})
    # "score" has no word outside its placeholders; "appTitle" differs in no locale.
    assert run(root, "--values").returncode == 0


def test_brand_name_uses_the_exemption_list(tmp_path):
    fr = {**FR, "appTitle": "ZapZap"}
    en = {**EN, "appTitle": "ZapZap"}
    de = {**DE, "appTitle": "ZapZap", "familyTutorial": "Anleitung"}
    root = project(tmp_path, fr=fr, en=en, de=de)
    assert run(root, "--values").returncode == 0


def test_missing_and_extra_keys_are_reported(tmp_path):
    de = {k: v for k, v in DE.items() if k != "hello"}
    de["stray"] = "Streuner"
    result = run(project(tmp_path, de=de), "--keys")
    assert result.returncode == 1
    assert "de lacks 1 key(s): hello" in result.stdout
    assert "de has key(s) the template lacks: stray" in result.stdout


def test_keys_mode_ignores_values(tmp_path):
    assert run(project(tmp_path), "--keys").returncode == 0


def test_values_mode_ignores_keys(tmp_path):
    de = {k: v for k, v in DE.items() if k != "hello"}
    de["familyTutorial"] = "Anleitung"
    assert run(project(tmp_path, de=de), "--values").returncode == 0


def test_invalid_json_exits_three(tmp_path):
    result = run(project(tmp_path, de="{not json"))
    assert result.returncode == 3
    assert "invalid JSON in app_de.arb" in result.stderr


def test_missing_l10n_yaml_exits_three(tmp_path):
    assert run(tmp_path).returncode == 3


def test_unused_lists_keys_no_dart_file_reads(tmp_path):
    root = project(tmp_path)
    (root / "lib" / "screen.dart").write_text("Text(l10n.hello); Text(l10n.score(1, 2));")
    (root / "lib" / "l10n" / "app_localizations.dart").write_text("String get appTitle; String get family;")
    result = run(root, "--unused")
    assert result.returncode == 1
    assert "3 template key(s) read by no .dart file under lib/: appTitle, family, familyTutorial" in result.stdout


def test_real_files_have_the_same_keys():
    """The committed ARB files: their key sets agree (the value check is a report, not a gate)."""
    result = subprocess.run([sys.executable, str(SCRIPT), "--keys"], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
