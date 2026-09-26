"""Tests for play_publish.py — no network, no credentials: the Google service is a fake.

    uv run --no-project --with pytest pytest scripts/test_play_publish.py

(CI: the `hooks` job. The Google libraries are imported only by build_service and
media_upload, which the tests replace, so pytest is the only dependency.)
"""

from __future__ import annotations

import io
import sys
from pathlib import Path
from typing import Any

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import play_publish as pp  # noqa: E402


# ------------------------------------------------------------------ fakes


class _Request:
    def __init__(self, service: "FakeService", method: str, kwargs: dict[str, Any]):
        self.service, self.method, self.kwargs = service, method, kwargs

    def execute(self, **execute_kwargs: Any) -> Any:
        self.service.calls.append((self.method, self.kwargs))
        self.service.execute_kwargs.append((self.method, execute_kwargs))
        answer = self.service.responses.get(self.method, {})
        if isinstance(answer, Exception):
            raise answer
        return answer


class _Resource:
    def __init__(self, service: "FakeService", path: str):
        self._service, self._path = service, path

    def __getattr__(self, name: str) -> Any:
        path = f"{self._path}.{name}" if self._path else name

        def call(**kwargs: Any) -> Any:
            if kwargs:  # a method call: edits().insert(packageName=...)
                return _Request(self._service, path, kwargs)
            return _Resource(self._service, path)  # a sub-resource: edits().tracks()

        return call


class FakeService(_Resource):
    """Mimics googleapiclient's `service.edits().tracks().update(...).execute()` chains."""

    def __init__(self, responses: dict[str, Any] | None = None):
        self.calls: list[tuple[str, dict[str, Any]]] = []
        self.execute_kwargs: list[tuple[str, dict[str, Any]]] = []
        self.responses = {
            "edits.insert": {"id": "edit-1"},
            "edits.tracks.list": {
                "tracks": [
                    {"track": "internal", "releases": [{"name": "1.0.1 (3)", "versionCodes": ["3"], "status": "completed"}]},
                    {"track": "production", "releases": [{"versionCodes": ["2"], "status": "completed"}]},
                ]
            },
            "edits.bundles.upload": {"versionCode": 4},
            "edits.listings.list": {"listings": [{"language": "en-US", "title": "ZapZap"}]},
        }
        self.responses.update(responses or {})
        super().__init__(self, "")

    def methods(self) -> list[str]:
        return [m for m, _ in self.calls]


def fake_media(path: Path, mimetype: str) -> tuple[str, str]:
    return (str(path), mimetype)


def write_listing_locale(root: Path, locale: str, *, notes_for: str | None = None) -> Path:
    d = root / "store_listing" / locale
    d.mkdir(parents=True, exist_ok=True)
    (d / "title.txt").write_text("ZapZap\n", encoding="utf-8")
    (d / "short_description.txt").write_text("Play a round\n", encoding="utf-8")
    (d / "full_description.txt").write_text("A long description\n", encoding="utf-8")
    if notes_for:
        (d / f"release_notes_v{notes_for}.txt").write_text(f"Notes {locale}\n", encoding="utf-8")
    phone = d / "screenshots" / "phone"  # the composed set; there is no shared fallback
    phone.mkdir(parents=True, exist_ok=True)
    for name in ("02_b.png", "01_a.png"):
        (phone / name).write_bytes(b"png")
    return d


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    (tmp_path / "frontend-flutter").mkdir()
    (tmp_path / "frontend-flutter" / "pubspec.yaml").write_text("name: zapzap\nversion: 1.1.0+4\n", encoding="utf-8")
    for locale in pp.NOTES_LOCALES:
        write_listing_locale(tmp_path, locale, notes_for="1.1.0")
    (tmp_path / "store_listing" / "assets").mkdir()
    (tmp_path / "store_listing" / "assets" / "feature_graphic.png").write_bytes(b"png")
    return tmp_path


def publish(repo: Path, service: FakeService, **opts: Any) -> str:
    out = io.StringIO()
    pp.cmd_publish(service, repo, pp.PublishOptions(**opts), media=fake_media, out=out)
    return out.getvalue()


def listing(repo: Path, service: FakeService, **opts: Any) -> str:
    out = io.StringIO()
    pp.cmd_listing(service, repo, pp.ListingOptions(**opts), media=fake_media, out=out)
    return out.getvalue()


# ------------------------------------------------------------------ local files


def test_version_and_notes(repo: Path) -> None:
    assert pp.read_version(repo) == ("1.1.0", 4)
    assert pp.read_release_notes(repo, "1.1.0", out=io.StringIO()) == [
        {"language": "en-US", "text": "Notes en-US"},
        {"language": "fr-FR", "text": "Notes fr-FR"},
    ]


def test_notes_over_500_characters_refused(repo: Path) -> None:
    (repo / "store_listing" / "fr-FR" / "release_notes_v1.1.0.txt").write_text("x" * 501, encoding="utf-8")
    with pytest.raises(pp.PublishError, match="501 characters; Play allows 500"):
        pp.read_release_notes(repo, "1.1.0", out=io.StringIO())


def test_notes_of_exactly_500_characters_accepted(repo: Path) -> None:
    (repo / "store_listing" / "en-US" / "release_notes_v1.1.0.txt").write_text("x" * 500 + "\n", encoding="utf-8")
    assert pp.read_release_notes(repo, "1.1.0", out=io.StringIO())[0]["text"] == "x" * 500


def test_missing_en_us_notes_refused(repo: Path) -> None:
    (repo / "store_listing" / "en-US" / "release_notes_v1.1.0.txt").unlink()
    with pytest.raises(pp.PublishError, match="missing"):
        pp.read_release_notes(repo, "1.1.0", out=io.StringIO())


def test_notes_fall_back_to_en_us(repo: Path) -> None:
    (repo / "store_listing" / "fr-FR" / "release_notes_v1.1.0.txt").unlink()
    log = io.StringIO()
    assert pp.read_release_notes(repo, "1.1.0", out=log) == [
        {"language": "en-US", "text": "Notes en-US"},
        {"language": "fr-FR", "text": "Notes en-US"},
    ]
    assert "no fr-FR release notes for 1.1.0, using en-US" in log.getvalue()


def test_extra_listing_locale_needs_no_release_notes(repo: Path) -> None:
    write_listing_locale(repo, "de-DE")  # a listing locale, no release_notes file at all
    assert "de-DE" in pp.listing_locales(repo)
    assert [n["language"] for n in pp.read_release_notes(repo, "1.1.0", out=io.StringIO())] == [
        "en-US",
        "fr-FR",
    ]


# ------------------------------------------------------------------ listing locales


def test_listing_locales_are_read_off_the_disk(repo: Path) -> None:
    assert pp.listing_locales(repo) == ["en-US", "fr-FR"]


def test_listing_locales_scale_to_ten(repo: Path) -> None:
    ten = ["de-DE", "en-US", "es-ES", "fr-FR", "it-IT", "ja-JP", "nl-NL", "pl-PL", "pt-BR", "ru-RU"]
    for locale in ten:
        write_listing_locale(repo, locale)
    assert pp.listing_locales(repo) == ten
    assert sorted(pp.read_listing(repo)) == ten


def test_listing_locales_skip_assets_and_directories_without_a_title(repo: Path) -> None:
    (repo / "store_listing" / "work-in-progress").mkdir()
    (repo / "store_listing" / "README.md").write_text("not a locale\n", encoding="utf-8")
    assert pp.listing_locales(repo) == ["en-US", "fr-FR"]
    assert pp.ASSETS_DIR == "assets"


def test_listing_locales_refused_when_none(tmp_path: Path) -> None:
    (tmp_path / "store_listing").mkdir()
    with pytest.raises(pp.PublishError, match="no locale directory with a title.txt"):
        pp.listing_locales(tmp_path)


def test_listing(repo: Path) -> None:
    listings = pp.read_listing(repo)
    assert listings["fr-FR"] == {
        "language": "fr-FR",
        "title": "ZapZap",
        "shortDescription": "Play a round",
        "fullDescription": "A long description",
    }
    (repo / "store_listing" / "en-US" / "title.txt").write_text("t" * 31, encoding="utf-8")
    with pytest.raises(pp.PublishError, match="Play allows 30"):
        pp.read_listing(repo)


def test_video_is_optional(repo: Path) -> None:
    assert "video" not in pp.read_listing(repo)["en-US"]
    (repo / "store_listing" / "en-US" / "video.txt").write_text(
        "https://www.youtube.com/watch?v=abc\n", encoding="utf-8"
    )
    listings = pp.read_listing(repo)
    assert listings["en-US"]["video"] == "https://www.youtube.com/watch?v=abc"
    assert "video" not in listings["fr-FR"]


def test_video_must_be_a_url(repo: Path) -> None:
    (repo / "store_listing" / "fr-FR" / "video.txt").write_text("abc\n", encoding="utf-8")
    with pytest.raises(pp.PublishError, match="must hold a YouTube URL"):
        pp.read_listing(repo)


# ------------------------------------------------------------------ graphics


def test_screenshots_in_name_order(repo: Path) -> None:
    _, shots = pp.graphics_files(repo, "en-US")
    assert [p.name for p in shots] == ["01_a.png", "02_b.png"]


def test_the_feature_graphic_falls_back_to_assets(repo: Path) -> None:
    feature, _ = pp.graphics_files(repo, "fr-FR")
    assert feature == repo / "store_listing" / "assets" / "feature_graphic.png"


def test_screenshots_have_no_shared_fallback(repo: Path) -> None:
    """A locale with no composed set is refused, never given raw or shared captures."""
    shared = repo / "store_listing" / "assets" / "screenshots" / "phone"
    shared.mkdir(parents=True)
    (shared / "01_raw.png").write_bytes(b"png")
    for shot in (repo / "store_listing" / "fr-FR" / "screenshots" / "phone").glob("*.png"):
        shot.unlink()
    with pytest.raises(pp.PublishError, match="capture_store_screenshots.sh, locale fr-FR"):
        pp.graphics_files(repo, "fr-FR")


def test_a_locale_feature_graphic_wins_over_assets(repo: Path) -> None:
    (repo / "store_listing" / "fr-FR" / "feature_graphic.png").write_bytes(b"png")
    feature, shots = pp.graphics_files(repo, "fr-FR")
    assert feature == repo / "store_listing" / "fr-FR" / "feature_graphic.png"
    assert [p.parent.parent.parent.name for p in shots] == ["fr-FR", "fr-FR"]


def test_a_jpeg_is_not_a_screenshot(repo: Path) -> None:
    phone = repo / "store_listing" / "fr-FR" / "screenshots" / "phone"
    (phone / "00_fr.jpg").write_bytes(b"jpeg")  # the glob is *.png only
    _, shots = pp.graphics_files(repo, "fr-FR")
    assert [p.name for p in shots] == ["01_a.png", "02_b.png"]


def test_more_than_eight_screenshots_refused(repo: Path) -> None:
    phone = repo / "store_listing" / "en-US" / "screenshots" / "phone"
    for i in range(9):
        (phone / f"1{i}.png").write_bytes(b"png")
    with pytest.raises(pp.PublishError, match="phone screenshots; Play allows 8"):
        pp.graphics_files(repo, "en-US")


def test_service_account_setup_named_when_missing(repo: Path) -> None:
    with pytest.raises(pp.PublishError, match="Play API access"):
        pp.read_service_account_path(repo)
    android = repo / "frontend-flutter" / "android"
    android.mkdir()
    (android / "key.properties").write_text("storeFile=/x\n", encoding="utf-8")
    with pytest.raises(pp.PublishError, match="no playServiceAccount= line"):
        pp.read_service_account_path(repo)
    key = repo / "sa.json"
    key.write_text("{}", encoding="utf-8")
    (android / "key.properties").write_text(f"playServiceAccount={key}\n", encoding="utf-8")
    assert pp.read_service_account_path(repo) == key
    # A relative path is relative to frontend-flutter/android/, next to key.properties.
    (android / "sa-rel.json").write_text("{}", encoding="utf-8")
    (android / "key.properties").write_text("playServiceAccount=sa-rel.json\n", encoding="utf-8")
    assert pp.read_service_account_path(repo) == android / "sa-rel.json"


def test_zapzap_constants() -> None:
    assert pp.PACKAGE == "com.zapzap.app"
    assert pp.NOTES_LOCALES == ("en-US", "fr-FR")
    assert pp.DEFAULT_AAB == "frontend-flutter/build/app/outputs/bundle/release/app-release.aab"
    assert pp.TRACKS == {"internal": "internal", "closed": "alpha", "production": "production"}


def test_pubspec_without_a_build_number_refused(repo: Path) -> None:
    (repo / "frontend-flutter" / "pubspec.yaml").write_text("name: zapzap\nversion: 1.1.0\n", encoding="utf-8")
    with pytest.raises(pp.PublishError, match="no `version: x.y.z\\+n` line"):
        pp.read_version(repo)


# ------------------------------------------------------------------ the edit


def test_validate_without_commit_deletes_the_edit(repo: Path) -> None:
    service = FakeService()
    out = publish(repo, service, track="internal")
    assert service.methods() == [
        "edits.insert",
        "edits.tracks.list",
        "edits.bundles.upload",
        "edits.tracks.update",
        "edits.validate",
        "edits.delete",
    ]
    assert "validated, nothing published" in out
    upload = dict(service.calls)["edits.bundles.upload"]
    assert upload["media_body"][1] == "application/octet-stream"
    assert dict(service.execute_kwargs)["edits.bundles.upload"] == {"num_retries": pp.NUM_RETRIES}
    update = dict(service.calls)["edits.tracks.update"]
    assert update["track"] == "internal"
    assert update["body"]["releases"] == [
        {
            "name": "1.1.0 (4)",
            "versionCodes": ["4"],
            "status": "completed",
            "releaseNotes": [
                {"language": "en-US", "text": "Notes en-US"},
                {"language": "fr-FR", "text": "Notes fr-FR"},
            ],
        }
    ]


def test_commit_only_with_flag(repo: Path) -> None:
    service = FakeService()
    publish(repo, service, track="closed", commit=True)
    assert service.methods()[-2:] == ["edits.validate", "edits.commit"]
    assert "edits.delete" not in service.methods()
    assert dict(service.calls)["edits.tracks.update"]["track"] == "alpha"


def test_low_version_code_refused_before_upload(repo: Path) -> None:
    service = FakeService({"edits.tracks.list": {"tracks": [{"track": "alpha", "releases": [{"versionCodes": ["4"]}]}]}})
    with pytest.raises(pp.PublishError, match="not above 4, already on track 'alpha'"):
        publish(repo, service, track="internal", commit=True)
    assert service.methods() == ["edits.insert", "edits.tracks.list", "edits.delete"]


def test_promote_moves_a_held_build_without_uploading(repo: Path) -> None:
    # versionCode 4 is on internal; production holds 2. Promoting it must not re-upload:
    # Play refuses a version code it has already seen.
    service = FakeService(
        {
            "edits.tracks.list": {
                "tracks": [
                    {"track": "internal", "releases": [{"versionCodes": ["4"], "status": "completed"}]},
                    {"track": "production", "releases": [{"versionCodes": ["2"], "status": "completed"}]},
                ]
            }
        }
    )
    out = publish(repo, service, track="production", promote=True, rollout=0.2, commit=True)
    assert "edits.bundles.upload" not in service.methods()
    assert "promoting versionCode 4 — no upload" in out
    update = dict(service.calls)["edits.tracks.update"]
    assert update["track"] == "production"
    assert update["body"]["releases"] == [
        {
            "name": "1.1.0 (4)",
            "versionCodes": ["4"],
            "status": "inProgress",
            "userFraction": 0.2,
            "releaseNotes": [
                {"language": "en-US", "text": "Notes en-US"},
                {"language": "fr-FR", "text": "Notes fr-FR"},
            ],
        }
    ]


def test_promote_refused_when_the_build_is_on_no_track(repo: Path) -> None:
    # The default fake holds 3 and 2; 4 has never been published.
    service = FakeService()
    with pytest.raises(pp.PublishError, match="is on no track yet"):
        publish(repo, service, track="production", promote=True, commit=True)
    assert "edits.bundles.upload" not in service.methods()


def test_promote_refused_when_already_on_the_target_track(repo: Path) -> None:
    service = FakeService(
        {
            "edits.tracks.list": {
                "tracks": [
                    {"track": "production", "releases": [{"versionCodes": ["4"], "status": "completed"}]},
                ]
            }
        }
    )
    with pytest.raises(pp.PublishError, match="already on track 'production': nothing to promote"):
        publish(repo, service, track="production", promote=True, commit=True)


def test_a_low_version_code_points_at_promote(repo: Path) -> None:
    service = FakeService({"edits.tracks.list": {"tracks": [{"track": "alpha", "releases": [{"versionCodes": ["4"]}]}]}})
    with pytest.raises(pp.PublishError, match="--promote"):
        publish(repo, service, track="production", commit=True)


def test_promote_takes_no_aab(repo: Path, capsys: Any) -> None:
    # main turns a PublishError into exit 1 and a line on stderr, it does not raise.
    assert pp.main(["publish", "--track", "production", "--promote", "--aab", "x.aab"]) == 1
    assert "--aab is unused" in capsys.readouterr().err


def test_bundle_version_code_mismatch_refused(repo: Path) -> None:
    service = FakeService({"edits.bundles.upload": {"versionCode": 5}})
    with pytest.raises(pp.PublishError, match="rebuild the bundle"):
        publish(repo, service, track="internal", commit=True)
    assert "edits.commit" not in service.methods()
    assert service.methods()[-1] == "edits.delete"


def test_upload_timeout_is_a_refusal_not_a_traceback(repo: Path) -> None:
    service = FakeService({"edits.bundles.upload": TimeoutError("The read operation timed out")})
    with pytest.raises(pp.PublishError, match="timed out after 300s"):
        publish(repo, service, track="internal", commit=True)
    assert "edits.commit" not in service.methods()
    assert service.methods()[-1] == "edits.delete"


def test_production_is_a_staged_rollout(repo: Path) -> None:
    service = FakeService()
    publish(repo, service, track="production")
    release = dict(service.calls)["edits.tracks.update"]["body"]["releases"][0]
    assert release["status"] == "inProgress"
    assert release["userFraction"] == 0.2


def test_draft(repo: Path) -> None:
    service = FakeService()
    publish(repo, service, track="production", draft=True)
    release = dict(service.calls)["edits.tracks.update"]["body"]["releases"][0]
    assert release["status"] == "draft"
    assert "userFraction" not in release


@pytest.mark.parametrize("fraction", [0, 1, 1.5, -0.1])
def test_rollout_outside_open_interval_refused(repo: Path, fraction: float) -> None:
    service = FakeService()
    with pytest.raises(pp.PublishError, match="strictly between 0 and 1"):
        publish(repo, service, track="production", rollout=fraction)
    assert service.calls == []


def test_listing_and_graphics(repo: Path) -> None:
    service = FakeService()
    publish(repo, service, track="internal", listing=True, graphics=True)
    methods = service.methods()
    assert methods.count("edits.listings.update") == 2  # one per listing locale
    # per locale: deleteall + 1 feature graphic, deleteall + 2 screenshots
    assert methods.count("edits.images.deleteall") == 4
    assert methods.count("edits.images.upload") == 6
    assert methods.index("edits.images.upload") < methods.index("edits.validate")
    shots = [
        c["media_body"][0]
        for m, c in service.calls
        if m == "edits.images.upload" and c["imageType"] == "phoneScreenshots" and c["language"] == "en-US"
    ]
    assert [Path(s).name for s in shots] == ["01_a.png", "02_b.png"]


def test_ten_listing_locales_do_not_require_ten_release_notes(repo: Path) -> None:
    """The trap: widening the listing must not make a release impossible."""
    ten = ["de-DE", "en-US", "es-ES", "fr-FR", "it-IT", "ja-JP", "nl-NL", "pl-PL", "pt-BR", "ru-RU"]
    for locale in ten:
        write_listing_locale(repo, locale)
    service = FakeService()
    publish(repo, service, track="internal", listing=True, graphics=True)
    methods = service.methods()
    assert methods.count("edits.listings.update") == 10
    assert methods.count("edits.images.deleteall") == 20
    notes = dict(service.calls)["edits.tracks.update"]["body"]["releases"][0]["releaseNotes"]
    assert [n["language"] for n in notes] == ["en-US", "fr-FR"]


def test_changes_not_sent_for_review_is_reported_not_retried(repo: Path) -> None:
    service = FakeService({"edits.commit": RuntimeError("400: changesNotSentForReview must be set")})
    with pytest.raises(pp.PublishError, match="changesNotSentForReview"):
        publish(repo, service, track="internal", commit=True)
    assert service.methods().count("edits.commit") == 1
    assert service.methods()[-1] == "edits.delete"


def test_status_is_read_only(repo: Path) -> None:
    service = FakeService()
    out = io.StringIO()
    pp.cmd_status(service, out=out)
    assert service.methods() == ["edits.insert", "edits.tracks.list", "edits.listings.list", "edits.delete"]
    assert "internal: 1.0.1 (3) [completed] versionCodes 3" in out.getvalue()


def test_rollout_flag_only_for_production() -> None:
    assert pp.main(["publish", "--track", "internal", "--rollout", "0.5"]) == 1


# ------------------------------------------------------------------ the listing subcommand


def test_listing_alone_touches_no_bundle_and_no_track(repo: Path) -> None:
    service = FakeService()
    out = listing(repo, service)
    assert service.methods() == [
        "edits.insert",
        "edits.listings.update",
        "edits.listings.update",
        "edits.validate",
        "edits.delete",
    ]
    assert "edits.bundles.upload" not in service.methods()
    assert "edits.tracks.update" not in service.methods()
    assert "edits.tracks.list" not in service.methods()
    assert "edits.commit" not in service.methods()
    assert "validated, nothing published" in out
    assert "listing locales: en-US, fr-FR" in out


def test_listing_alone_needs_no_pubspec(tmp_path: Path) -> None:
    """No pubspec.yaml, no bundle: the listing is publishable without a version bump."""
    write_listing_locale(tmp_path, "en-US")
    write_listing_locale(tmp_path, "fr-FR")
    assert not (tmp_path / "frontend-flutter" / "pubspec.yaml").exists()
    service = FakeService()
    listing(tmp_path, service)
    assert service.methods().count("edits.listings.update") == 2


def test_listing_commit_publishes_and_warns_about_the_missing_rollout(repo: Path) -> None:
    service = FakeService()
    out = listing(repo, service, commit=True)
    assert service.methods()[-2:] == ["edits.validate", "edits.commit"]
    assert "edits.delete" not in service.methods()
    assert "no userFraction" in out
    assert "live, no rollout" in out


def test_listing_graphics(repo: Path) -> None:
    service = FakeService()
    listing(repo, service, graphics=True)
    methods = service.methods()
    assert methods.count("edits.listings.update") == 2
    # per locale: deleteall + 1 feature graphic, deleteall + 2 screenshots
    assert methods.count("edits.images.deleteall") == 4
    assert methods.count("edits.images.upload") == 6
    assert methods.index("edits.images.upload") < methods.index("edits.validate")
    assert "edits.bundles.upload" not in methods


def test_listing_scales_to_ten_locales(repo: Path) -> None:
    for locale in ("de-DE", "es-ES", "it-IT", "ja-JP", "nl-NL", "pl-PL", "pt-BR", "ru-RU"):
        write_listing_locale(repo, locale)
    service = FakeService()
    out = listing(repo, service, graphics=True)
    assert service.methods().count("edits.listings.update") == 10
    assert service.methods().count("edits.images.deleteall") == 20
    assert "de-DE" in out and "ru-RU" in out


def test_listing_bad_file_stops_before_the_edit(repo: Path) -> None:
    (repo / "store_listing" / "fr-FR" / "short_description.txt").write_text("s" * 81, encoding="utf-8")
    service = FakeService()
    with pytest.raises(pp.PublishError, match="Play allows 80"):
        listing(repo, service)
    assert service.calls == []


def test_listing_changes_not_sent_for_review_is_reported(repo: Path) -> None:
    service = FakeService({"edits.commit": RuntimeError("400: changesNotSentForReview must be set")})
    with pytest.raises(pp.PublishError, match="changesNotSentForReview"):
        listing(repo, service, commit=True)
    assert service.methods()[-1] == "edits.delete"


def test_listing_subcommand_parses() -> None:
    args = pp.parse_args(["listing", "--graphics", "--commit"])
    assert (args.command, args.graphics, args.commit) == ("listing", True, True)
    bare = pp.parse_args(["listing"])
    assert (bare.graphics, bare.commit) == (False, False)
