#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "google-api-python-client>=2.100",
#   "google-auth>=2.23",
#   "google-auth-httplib2>=0.2",
#   "httplib2>=0.22",
# ]
# ///
"""Publish ZapZap to Google Play through the Play Developer Publishing API (v3).

    uv run --script scripts/play_publish.py status
    uv run --script scripts/play_publish.py publish --track internal
    uv run --script scripts/play_publish.py publish --track internal --commit
    uv run --script scripts/play_publish.py listing --graphics

Run from the checkout that built the bundle. Every change goes through one *edit*: nothing
is visible in the Play Console until `edits.commit`, which happens only with --commit.
Without it the edit is validated by Google and then deleted.

`listing` is the store listing alone — title, descriptions, an optional promo video, and
with --graphics the feature graphic and the phone screenshots. It never reads pubspec.yaml,
never runs verify_aab.sh and never uploads a bundle, so the listing can be rewritten without
a version bump. A listing has no `userFraction`: `listing --commit` is live at once, for
everyone, with no staged rollout.

The service-account key is named by `playServiceAccount=` in
frontend-flutter/android/key.properties; the one-time setup is in
.claude/skills/release-android/SKILL.md, "Play API access". No CI job runs this script:
the key never leaves the developer's machine.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable, TextIO

PACKAGE = "com.zapzap.app"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
# Release notes stay bilingual on purpose: a locale added to store_listing/ must not make a
# third release-notes file mandatory at the next release. A missing file falls back to en-US.
NOTES_LOCALES = ("en-US", "fr-FR")  # en-US first: the fallback
# The listing locales are *not* a constant: listing_locales() reads them off the disk, so
# adding a language to the listing is creating a directory — this file does not change.
LISTING_ROOT = "store_listing"
FLUTTER_DIR = "frontend-flutter"
ASSETS_DIR = "assets"
NOTES_LIMIT = 500
LISTING_FILES = {  # file -> (API field, Play's limit)
    "title.txt": ("title", 30),
    "short_description.txt": ("shortDescription", 80),
    "full_description.txt": ("fullDescription", 4000),
}
# Optional: the `video` field of the androidpublisher Listing resource, a YouTube URL.
# No file means the field is not sent at all, and Play keeps whatever it already has.
VIDEO_FILE = "video.txt"
VIDEO_LIMIT = 2048
MAX_PHONE_SCREENSHOTS = 8  # Play's limit
# The Console's "Closed testing" is the API track `alpha`.
TRACKS = {"internal": "internal", "closed": "alpha", "production": "production"}
DEFAULT_ROLLOUT = 0.2
DEFAULT_AAB = "frontend-flutter/build/app/outputs/bundle/release/app-release.aab"
HTTP_TIMEOUT = 300  # seconds — httplib2's default socket has no read timeout at all
NUM_RETRIES = 5  # googleapiclient retries an upload this many times before giving up
SETUP_HINT = (
    "One-time setup: .claude/skills/release-android/SKILL.md, section 'Play API access' "
    "(service account, JSON key at ~/.config/zapzap/play-service-account.json, "
    "then playServiceAccount=<absolute path> in frontend-flutter/android/key.properties)."
)
NO_ROLLOUT_WARNING = (
    "note: a store listing has no userFraction — unlike a bundle it cannot be staged. "
    "--commit publishes the text (and with --graphics the images) to everyone at once, in "
    "every locale listed above, as soon as Play accepts the edit."
)


class PublishError(Exception):
    """A refusal or failure with a message meant for the person running the script."""


# ----------------------------------------------------------------- local files


def repo_root() -> Path:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True
        )
        return Path(out.stdout.strip())
    except (OSError, subprocess.CalledProcessError):
        return Path(__file__).resolve().parents[1]


def read_version(root: Path) -> tuple[str, int]:
    """`version: x.y.z+n` from frontend-flutter/pubspec.yaml -> ("x.y.z", n)."""
    text = (root / FLUTTER_DIR / "pubspec.yaml").read_text(encoding="utf-8")
    m = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$", text, re.MULTILINE)
    if not m:
        raise PublishError(f"{FLUTTER_DIR}/pubspec.yaml has no `version: x.y.z+n` line")
    return m.group(1), int(m.group(2))


def read_service_account_path(root: Path) -> Path:
    props = root / FLUTTER_DIR / "android" / "key.properties"
    if not props.is_file():
        raise PublishError(f"{props} does not exist. {SETUP_HINT}")
    value = None
    for line in props.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("playServiceAccount="):
            value = line.split("=", 1)[1].strip()
    if not value:
        raise PublishError(f"no playServiceAccount= line in {props}. {SETUP_HINT}")
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / FLUTTER_DIR / "android" / path
    if not path.is_file():
        raise PublishError(f"the service-account key {path} does not exist. {SETUP_HINT}")
    return path


def _read_text(path: Path, limit: int) -> str:
    if not path.is_file():
        raise PublishError(f"missing {path}")
    text = path.read_text(encoding="utf-8").strip()
    if not text:
        raise PublishError(f"{path} is empty")
    if len(text) > limit:
        raise PublishError(f"{path} is {len(text)} characters; Play allows {limit}")
    return text


def listing_locales(root: Path) -> list[str]:
    """The store-listing locales, read off the disk rather than held in a constant.

    A locale is a directory under store_listing/ holding a title.txt; `assets/` and any
    directory without one (a guide, a translation in progress) is skipped. Adding a language
    to the listing is therefore creating its directory — there is no second list to drift.
    """
    base = root / LISTING_ROOT
    if not base.is_dir():
        raise PublishError(f"missing {base}")
    locales = sorted(
        d.name
        for d in base.iterdir()
        if d.is_dir() and d.name != ASSETS_DIR and (d / "title.txt").is_file()
    )
    if not locales:
        raise PublishError(f"no locale directory with a title.txt under {base}")
    return locales


def read_release_notes(root: Path, version: str, out: TextIO = sys.stderr) -> list[dict[str, str]]:
    """The release notes, for NOTES_LOCALES only, each falling back to en-US when absent.

    A listing locale outside NOTES_LOCALES requires nothing: a language can be added to the
    store listing without making a third release-notes file mandatory at every release.
    """
    fallback = NOTES_LOCALES[0]
    notes = []
    for locale in NOTES_LOCALES:
        path = root / LISTING_ROOT / locale / f"release_notes_v{version}.txt"
        if not path.is_file() and locale != fallback:
            path = root / LISTING_ROOT / fallback / f"release_notes_v{version}.txt"
            print(f"note: no {locale} release notes for {version}, using {fallback}", file=out)
        notes.append({"language": locale, "text": _read_text(path, NOTES_LIMIT)})
    return notes


def read_listing(root: Path) -> dict[str, dict[str, str]]:
    listings = {}
    for locale in listing_locales(root):
        body = {"language": locale}
        for name, (field, limit) in LISTING_FILES.items():
            body[field] = _read_text(root / LISTING_ROOT / locale / name, limit)
        video = root / LISTING_ROOT / locale / VIDEO_FILE
        if video.is_file():  # optional; absent means the field is not sent at all
            url = _read_text(video, VIDEO_LIMIT)
            if not url.startswith(("http://", "https://")):
                raise PublishError(f"{video} must hold a YouTube URL, got {url!r}")
            body["video"] = url
        listings[locale] = body
    return listings


def graphics_files(root: Path, locale: str) -> tuple[Path, list[Path]]:
    """The feature graphic and the phone screenshots for one locale.

    The feature graphic: store_listing/<locale>/ first, store_listing/assets/ as the fallback
    — still the nominal path, a localised feature graphic is opt-in. The screenshots have no
    fallback: only a locale's composed set, store_listing/<locale>/screenshots/phone/
    (scripts/capture_store_screenshots.sh), is uploaded: a shared set would show one language
    in every listing. The screenshot glob
    is `*.png` only, so a JPEG dropped in that directory is ignored in silence.
    """
    base = root / LISTING_ROOT
    feature = base / locale / "feature_graphic.png"
    if not feature.is_file():
        feature = base / ASSETS_DIR / "feature_graphic.png"
    if not feature.is_file():
        raise PublishError(f"missing {feature}")
    phone = base / locale / "screenshots" / "phone"
    shots = _pngs(phone)
    if not shots:
        raise PublishError(
            f"no PNG in {phone}: capture the locale's screenshots first "
            f"(scripts/capture_store_screenshots.sh, locale {locale})"
        )
    if len(shots) > MAX_PHONE_SCREENSHOTS:
        raise PublishError(f"{len(shots)} phone screenshots; Play allows {MAX_PHONE_SCREENSHOTS}")
    return feature, shots


def _pngs(directory: Path) -> list[Path]:
    if not directory.is_dir():
        return []
    return sorted(directory.glob("*.png"), key=lambda p: p.name)


def read_graphics(root: Path, locales: Iterable[str]) -> dict[str, tuple[Path, list[Path]]]:
    return {locale: graphics_files(root, locale) for locale in locales}


def build_release(
    version: str, code: int, notes: list[dict[str, str]], track: str, draft: bool, rollout: float
) -> dict[str, Any]:
    release: dict[str, Any] = {
        "name": f"{version} ({code})",
        "versionCodes": [str(code)],
        "releaseNotes": notes,
    }
    if draft:
        release["status"] = "draft"
    elif track == "production":
        release["status"] = "inProgress"
        release["userFraction"] = rollout
    else:
        release["status"] = "completed"
    return release


# ----------------------------------------------------------------- Google side


def build_service(key_path: Path) -> Any:  # pragma: no cover - needs real credentials
    import httplib2
    from google.oauth2 import service_account
    from google_auth_httplib2 import AuthorizedHttp
    from googleapiclient.discovery import build

    credentials = service_account.Credentials.from_service_account_file(
        str(key_path), scopes=[SCOPE]
    )
    # httplib2's default socket never times out on a read, so a stalled bundle upload would
    # hang and then raise a bare TimeoutError (countscore learnt it on a 60 MB bundle).
    http = AuthorizedHttp(credentials, http=httplib2.Http(timeout=HTTP_TIMEOUT))
    return build("androidpublisher", "v3", http=http, cache_discovery=False)


def media_upload(path: Path, mimetype: str) -> Any:  # pragma: no cover - thin wrapper
    from googleapiclient.http import MediaFileUpload

    return MediaFileUpload(str(path), mimetype=mimetype, resumable=True)


def max_version_code(service: Any, edit_id: str) -> tuple[int, str]:
    """Highest version code on any track, and the track holding it."""
    tracks = service.edits().tracks().list(packageName=PACKAGE, editId=edit_id).execute()
    best, where = 0, "none"
    for track in tracks.get("tracks", []):
        for release in track.get("releases", []):
            for vc in release.get("versionCodes", []):
                if int(vc) > best:
                    best, where = int(vc), track.get("track", "?")
    return best, where


def version_codes_on_track(service: Any, edit_id: str, api_track: str) -> set[int]:
    """The version codes already released on one track."""
    tracks = service.edits().tracks().list(packageName=PACKAGE, editId=edit_id).execute()
    return {
        int(vc)
        for track in tracks.get("tracks", [])
        if track.get("track") == api_track
        for release in track.get("releases", [])
        for vc in release.get("versionCodes", [])
    }


def describe_tracks(tracks: dict[str, Any]) -> list[str]:
    lines = []
    for track in tracks.get("tracks", []):
        releases = track.get("releases", [])
        if not releases:
            lines.append(f"  {track.get('track')}: no release")
        for r in releases:
            fraction = f" {float(r['userFraction']):.0%}" if "userFraction" in r else ""
            codes = ",".join(r.get("versionCodes", [])) or "-"
            lines.append(
                f"  {track.get('track')}: {r.get('name', '(unnamed)')} "
                f"[{r.get('status', '?')}{fraction}] versionCodes {codes}"
            )
    return lines or ["  no tracks"]


def push_listings(
    edits: Any, edit_id: str, listings: dict[str, dict[str, str]], out: TextIO
) -> None:
    for locale, body in listings.items():
        edits.listings().update(
            packageName=PACKAGE, editId=edit_id, language=locale, body=body
        ).execute()
        extra = " + promo video" if "video" in body else ""
        print(f"listing {locale} updated{extra}", file=out)


def push_graphics(
    edits: Any,
    edit_id: str,
    graphics: dict[str, tuple[Path, list[Path]]],
    media: Callable[[Path, str], Any],
    out: TextIO,
) -> None:
    for locale, (feature, shots) in graphics.items():
        images = edits.images()
        for image_type, files in (("featureGraphic", [feature]), ("phoneScreenshots", shots)):
            images.deleteall(
                packageName=PACKAGE, editId=edit_id, language=locale, imageType=image_type
            ).execute()
            for f in files:
                images.upload(
                    packageName=PACKAGE,
                    editId=edit_id,
                    language=locale,
                    imageType=image_type,
                    media_body=media(f, "image/png"),
                ).execute(num_retries=NUM_RETRIES)
        print(f"graphics {locale}: feature graphic + {len(shots)} phone screenshots", file=out)


def commit_edit(edits: Any, edit_id: str) -> None:
    """edits.commit, with Play's `changesNotSentForReview` answer turned into a refusal."""
    try:
        edits.commit(packageName=PACKAGE, editId=edit_id).execute()
    except Exception as err:  # googleapiclient.errors.HttpError
        if "changesNotSentForReview" in str(err):
            raise PublishError(
                "Play refused the commit and asks for changesNotSentForReview: this app's "
                "changes are sent for review from the Console (Publishing overview), not "
                "automatically. Nothing was published. Google's answer:\n"
                f"{err}"
            ) from err
        raise


def discard_edit(edits: Any, edit_id: str) -> None:
    try:
        edits.delete(packageName=PACKAGE, editId=edit_id).execute()
    except Exception as err:  # the edit expires on its own; never mask the real error
        print(f"warning: could not delete edit {edit_id}: {err}", file=sys.stderr)


def cmd_status(service: Any, out: TextIO = sys.stdout) -> None:
    edits = service.edits()
    edit_id = edits.insert(packageName=PACKAGE, body={}).execute()["id"]
    try:
        tracks = edits.tracks().list(packageName=PACKAGE, editId=edit_id).execute()
        listings = edits.listings().list(packageName=PACKAGE, editId=edit_id).execute()
        print(f"{PACKAGE} — tracks (Console 'Closed testing' is API track 'alpha')", file=out)
        for line in describe_tracks(tracks):
            print(line, file=out)
        print("listings", file=out)
        for listing in listings.get("listings", []) or []:
            print(
                f"  {listing.get('language')}: {listing.get('title', '')!r} — "
                f"short {len(listing.get('shortDescription', ''))} chars, "
                f"full {len(listing.get('fullDescription', ''))} chars",
                file=out,
            )
    finally:
        discard_edit(edits, edit_id)


@dataclass
class ListingOptions:
    graphics: bool = False
    commit: bool = False


def cmd_listing(
    service: Any,
    root: Path,
    opts: ListingOptions,
    media: Callable[[Path, str], Any] = media_upload,
    out: TextIO = sys.stdout,
) -> None:
    """The store listing alone — no pubspec.yaml, no verify_aab.sh, no bundle, no track."""
    # Read and check every local file before opening an edit.
    listings = read_listing(root)
    graphics = read_graphics(root, listings) if opts.graphics else {}
    print(f"listing locales: {', '.join(listings)}", file=out)
    if opts.commit:
        print(NO_ROLLOUT_WARNING, file=out)

    edits = service.edits()
    edit_id = edits.insert(packageName=PACKAGE, body={}).execute()["id"]
    committed = False
    try:
        push_listings(edits, edit_id, listings, out)
        push_graphics(edits, edit_id, graphics, media, out)

        edits.validate(packageName=PACKAGE, editId=edit_id).execute()
        print("edits.validate OK", file=out)

        if not opts.commit:
            print("validated, nothing published (rerun with --commit to publish)", file=out)
            return
        commit_edit(edits, edit_id)
        committed = True
        print(f"committed: store listing for {', '.join(listings)} — live, no rollout", file=out)
    finally:
        if not committed:
            discard_edit(edits, edit_id)


@dataclass
class PublishOptions:
    track: str
    rollout: float = DEFAULT_ROLLOUT
    draft: bool = False
    listing: bool = False
    graphics: bool = False
    commit: bool = False
    aab: Path = Path(DEFAULT_AAB)
    promote: bool = False


def upload_bundle(
    edits: Any,
    edit_id: str,
    opts: "PublishOptions",
    code: int,
    media: Callable[[Path, str], Any],
    out: TextIO,
) -> None:
    """Send the bundle to Play and check it carries the version code pubspec.yaml names."""
    try:
        uploaded = (
            edits.bundles()
            .upload(
                packageName=PACKAGE,
                editId=edit_id,
                media_body=media(opts.aab, "application/octet-stream"),
            )
            .execute(num_retries=NUM_RETRIES)
        )
    except TimeoutError as err:
        raise PublishError(
            f"the bundle upload timed out after {HTTP_TIMEOUT}s and {NUM_RETRIES} retries. "
            "Nothing was committed and the edit is discarded: rerun the same command."
        ) from err
    if int(uploaded.get("versionCode", -1)) != code:
        raise PublishError(
            f"Play read versionCode {uploaded.get('versionCode')} from the bundle, "
            f"pubspec.yaml says {code}: rebuild the bundle"
        )
    print(f"uploaded {opts.aab} — versionCode {code}", file=out)


def cmd_publish(
    service: Any,
    root: Path,
    opts: PublishOptions,
    media: Callable[[Path, str], Any] = media_upload,
    out: TextIO = sys.stdout,
) -> None:
    if opts.track not in TRACKS:
        raise PublishError(f"track must be one of {', '.join(TRACKS)}")
    if not 0 < opts.rollout < 1:
        raise PublishError(f"rollout must be strictly between 0 and 1, got {opts.rollout}")
    version, code = read_version(root)
    # Read and check every local file before opening an edit.
    notes = read_release_notes(root, version)
    listings = read_listing(root) if opts.listing else {}
    graphics = read_graphics(root, listing_locales(root)) if opts.graphics else {}
    release = build_release(version, code, notes, opts.track, opts.draft, opts.rollout)
    api_track = TRACKS[opts.track]

    edits = service.edits()
    edit_id = edits.insert(packageName=PACKAGE, body={}).execute()["id"]
    committed = False
    try:
        if opts.promote:
            # Promotion moves a build Play already holds to another track. Play refuses a
            # versionCode it has seen before, so the bundle is referenced, never re-uploaded.
            highest, where = max_version_code(service, edit_id)
            if code > highest:
                raise PublishError(
                    f"versionCode {code} (pubspec.yaml) is on no track yet — the highest Play "
                    f"holds is {highest} on '{where}'. Publish it first, without --promote."
                )
            if code in version_codes_on_track(service, edit_id, api_track):
                raise PublishError(
                    f"versionCode {code} is already on track '{api_track}': nothing to promote."
                )
            print(f"promoting versionCode {code} — no upload", file=out)
        else:
            highest, where = max_version_code(service, edit_id)
            if code <= highest:
                raise PublishError(
                    f"versionCode {code} (pubspec.yaml) is not above {highest}, already on track "
                    f"'{where}'. Bump `version:` in {FLUTTER_DIR}/pubspec.yaml and rebuild, or "
                    f"promote the "
                    f"build Play already holds with --promote."
                )
            upload_bundle(edits, edit_id, opts, code, media, out)

        edits.tracks().update(
            packageName=PACKAGE,
            editId=edit_id,
            track=api_track,
            body={"track": api_track, "releases": [release]},
        ).execute()
        fraction = f" {release['userFraction']:.0%}" if "userFraction" in release else ""
        print(f"track {api_track}: {release['name']} [{release['status']}{fraction}]", file=out)

        push_listings(edits, edit_id, listings, out)
        push_graphics(edits, edit_id, graphics, media, out)

        edits.validate(packageName=PACKAGE, editId=edit_id).execute()
        print("edits.validate OK", file=out)

        if not opts.commit:
            print("validated, nothing published (rerun with --commit to publish)", file=out)
            return
        commit_edit(edits, edit_id)
        committed = True
        print(f"committed: {release['name']} on {api_track}", file=out)
    finally:
        if not committed:
            discard_edit(edits, edit_id)


# ----------------------------------------------------------------- entry point


def verify_aab(root: Path, aab: Path) -> None:
    script = Path(__file__).resolve().with_name("verify_aab.sh")
    if subprocess.run([str(script), str(aab)], cwd=root).returncode != 0:
        raise PublishError("verify_aab.sh failed — nothing was sent to Play")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status", help="read-only: releases per track and the current listings")
    pub = sub.add_parser("publish", help="upload the bundle to a track, validate, and commit on --commit")
    pub.add_argument("--track", required=True, choices=sorted(TRACKS))
    pub.add_argument("--rollout", type=float, help=f"production only, default {DEFAULT_ROLLOUT}")
    pub.add_argument("--draft", action="store_true", help="create the release as a draft")
    pub.add_argument("--listing", action="store_true", help="update title and descriptions")
    pub.add_argument("--graphics", action="store_true", help="replace feature graphic and phone screenshots")
    pub.add_argument("--commit", action="store_true", help="publish the edit; without it, validate only")
    pub.add_argument("--aab", type=Path, default=None, help=f"default {DEFAULT_AAB}")
    pub.add_argument(
        "--promote",
        action="store_true",
        help="move a build Play already holds to this track; no bundle is built or uploaded",
    )
    lst = sub.add_parser(
        "listing",
        help="the store listing alone — no bundle, no version bump; --commit is live at once",
    )
    lst.add_argument("--graphics", action="store_true", help="replace feature graphic and phone screenshots")
    lst.add_argument("--commit", action="store_true", help="publish the edit; without it, validate only")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    root = repo_root()
    try:
        if args.command == "status":
            cmd_status(build_service(read_service_account_path(root)))
            return 0
        if args.command == "listing":
            key = read_service_account_path(root)
            cmd_listing(
                build_service(key),
                root,
                ListingOptions(graphics=args.graphics, commit=args.commit),
            )
            return 0
        if args.rollout is not None and args.track != "production":
            raise PublishError("--rollout applies to --track production only")
        aab = args.aab or root / DEFAULT_AAB
        if args.promote and args.aab is not None:
            raise PublishError("--promote references a build Play already holds: --aab is unused")
        opts = PublishOptions(
            track=args.track,
            rollout=DEFAULT_ROLLOUT if args.rollout is None else args.rollout,
            draft=args.draft,
            listing=args.listing,
            graphics=args.graphics,
            commit=args.commit,
            aab=aab,
            promote=args.promote,
        )
        if not 0 < opts.rollout < 1:
            raise PublishError(f"rollout must be strictly between 0 and 1, got {opts.rollout}")
        key = read_service_account_path(root)
        # A promotion builds and uploads nothing, so there is no local bundle to verify — the
        # one Play holds was verified when it was published.
        if not opts.promote:
            verify_aab(root, aab)
        cmd_publish(build_service(key), root, opts)
        return 0
    except PublishError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
