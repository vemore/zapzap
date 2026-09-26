#!/usr/bin/env python3
"""Render privacy_policy.md to nginx/privacy.html, the page served at /privacy.

Google Play links to that URL, and a policy there that does not match what the app does is a
policy violation. Generating the page instead of hand-writing it keeps the two the same
document: edit `privacy_policy.md`, run this, commit both. The proxy image bakes the page in
(nginx/Dockerfile) and nginx/nginx.conf serves it at /privacy, so it goes live with the next
deploy of the proxy image.

    python3 scripts/build_privacy_page.py            # write nginx/privacy.html
    python3 scripts/build_privacy_page.py --check    # write nothing; fail if it is stale

CI's image job runs `--check` (.github/workflows/ci.yml), so a stale page fails the build.

Requires `pandoc` on PATH, at PANDOC_VERSION below: another version can render the same
Markdown differently, and `--check` would then report a stale page that is not. The output
is standalone on purpose — no CDN, no font, no script.
"""

from __future__ import annotations

import argparse
import difflib
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "privacy_policy.md"
OUTPUT = ROOT / "nginx" / "privacy.html"

PANDOC_VERSION = "3.6.4"

# Light palette on :root, dark under prefers-color-scheme: the page follows the reader's
# system setting without any script.
TEMPLATE = """<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ZapZap — Confidentialité / Privacy</title>
<meta name="description" content="Politique de confidentialité de ZapZap / ZapZap's privacy policy.">
<style>
:root {{
  color-scheme: light dark;
  --bg: #f6f7f9;
  --surface: #ffffff;
  --text: #1b1d21;
  --muted: #5a5f69;
  --rule: #dfe2e7;
  --accent: #b7791f;
}}
@media (prefers-color-scheme: dark) {{
  :root {{
    --bg: #0f172a;
    --surface: #1e293b;
    --text: #e5e7eb;
    --muted: #9ca3af;
    --rule: #334155;
    --accent: #fbbf24;
  }}
}}
* {{ box-sizing: border-box; }}
body {{
  margin: 0;
  padding: 2rem 1rem 4rem;
  background: var(--bg);
  color: var(--text);
  font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
}}
main {{
  max-width: 46rem;
  margin: 0 auto;
  background: var(--surface);
  border: 1px solid var(--rule);
  border-radius: 12px;
  padding: 2rem 1.5rem;
  overflow-wrap: anywhere;
}}
h1, h2, h3 {{ line-height: 1.25; }}
h1 {{ font-size: 1.7rem; margin: 0 0 1rem; }}
h2 {{ font-size: 1.35rem; margin: 2rem 0 0.75rem; }}
h3 {{ font-size: 1.05rem; margin: 1.5rem 0 0.5rem; color: var(--muted); }}
a {{ color: var(--accent); }}
ul {{ padding-left: 1.3rem; }}
li {{ margin: 0.35rem 0; }}
hr {{ border: 0; border-top: 1px solid var(--rule); margin: 2rem 0; }}
</style>
</head>
<body>
<main>
{body}
</main>
</body>
</html>
"""


def pandoc_version() -> str | None:
    """The version of the pandoc on PATH, or None when there is none."""
    if shutil.which("pandoc") is None:
        return None
    out = subprocess.run(["pandoc", "--version"], capture_output=True, text=True, check=True)
    return out.stdout.splitlines()[0].split()[-1]


def render() -> str:
    """The whole page, exactly as it is written to OUTPUT."""
    body = subprocess.run(
        ["pandoc", "--from", "gfm", "--to", "html", "--no-highlight", str(SOURCE)],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    return TEMPLATE.format(body=body)


def check() -> int:
    have = pandoc_version()
    if have != PANDOC_VERSION:
        print(
            f"warning: pandoc {have} is on PATH, the page is pinned to {PANDOC_VERSION} — "
            "a difference below may be the version, not the policy",
            file=sys.stderr,
        )
    committed = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
    diff = list(
        difflib.unified_diff(
            committed.splitlines(keepends=True),
            render().splitlines(keepends=True),
            "nginx/privacy.html (committed)",
            "nginx/privacy.html (rendered from privacy_policy.md)",
        )
    )
    if diff:
        sys.stdout.writelines(diff)
        print(
            "error: nginx/privacy.html is stale against privacy_policy.md — "
            "run `python3 scripts/build_privacy_page.py` and commit both",
            file=sys.stderr,
        )
        return 1
    print("nginx/privacy.html matches privacy_policy.md")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Render privacy_policy.md to nginx/privacy.html.")
    parser.add_argument(
        "--check", action="store_true", help="write nothing; fail if the committed page is stale"
    )
    args = parser.parse_args()
    if shutil.which("pandoc") is None:
        print("pandoc is not on PATH — install it (apt install pandoc).", file=sys.stderr)
        return 1
    if args.check:
        return check()
    OUTPUT.write_text(render(), encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size} B)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
