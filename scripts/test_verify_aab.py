"""Tests for verify_aab.sh — no Flutter build: a fake bundle, signed by throwaway keystores.

    uv run --no-project --with pytest pytest scripts/test_verify_aab.py

A bundle here is a zip holding what the script reads — base/manifest/AndroidManifest.xml
and base/lib/<abi>/*.so, the libraries compiled by cc with the page alignment under test —
signed with jarsigner. Needs a JDK (keytool, jarsigner), cc, unzip and readelf: the CI
runner has all of them; a machine without one skips the module.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import time
import zipfile
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().with_name("verify_aab.sh")
TOOLS = ("keytool", "jarsigner", "cc", "unzip", "readelf")
MANIFEST_REL = "frontend-flutter/build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml"
PASSWORD = "test-password"

missing = [t for t in TOOLS if shutil.which(t) is None]
# CI sets VERIFY_AAB_REQUIRE_TOOLS=1: there a missing tool is a failure, never a silent skip.
if missing and os.environ.get("VERIFY_AAB_REQUIRE_TOOLS") == "1":
    raise RuntimeError(f"verify_aab.sh tests need {', '.join(missing)}")
pytestmark = pytest.mark.skipif(bool(missing), reason=f"missing {', '.join(missing)}")


def make_keystore(path: Path, alias: str, dname: str) -> Path:
    subprocess.run(
        ["keytool", "-genkeypair", "-keystore", str(path), "-alias", alias, "-keyalg", "RSA",
         "-keysize", "2048", "-validity", "2", "-dname", dname,
         "-storepass", PASSWORD, "-keypass", PASSWORD],
        check=True, capture_output=True,
    )
    return path


def make_so(path: Path, page: int) -> Path:
    src = path.with_suffix(".c")
    src.write_text("int zapzap(void) { return 1; }\n", encoding="utf-8")
    subprocess.run(
        ["cc", "-shared", "-fPIC", f"-Wl,-z,max-page-size={page}", "-o", str(path), str(src)],
        check=True, capture_output=True,
    )
    return path


@pytest.fixture(scope="session")
def keys(tmp_path_factory: pytest.TempPathFactory) -> dict[str, Path]:
    d = tmp_path_factory.mktemp("keys")
    return {
        "upload": make_keystore(d / "upload.jks", "zapzap-upload", "CN=ZapZap Upload, O=ZapZap"),
        "debug": make_keystore(d / "debug.jks", "androiddebugkey", "CN=Android Debug, O=Android, C=US"),
        "other": make_keystore(d / "other.jks", "someone", "CN=Someone Else"),
    }


@pytest.fixture(scope="session")
def libs(tmp_path_factory: pytest.TempPathFactory) -> dict[int, Path]:
    d = tmp_path_factory.mktemp("libs")
    return {page: make_so(d / f"lib{page}.so", page) for page in (4096, 16384)}


class Repo:
    """A repository root as verify_aab.sh sees it, with a bundle built into it."""

    def __init__(self, root: Path, keys: dict[str, Path], libs: dict[int, Path]):
        self.root, self.keys, self.libs = root, keys, libs
        self.app = root / "frontend-flutter"
        self.aab = self.app / "build/app/outputs/bundle/release/app-release.aab"
        (self.app / "android").mkdir(parents=True)
        self.pubspec("1.0.0+1")
        (self.app / "android" / "key.properties").write_text(
            f"storeFile={keys['upload']}\nstorePassword={PASSWORD}\n"
            f"keyAlias=zapzap-upload\nkeyPassword={PASSWORD}\n",
            encoding="utf-8",
        )

    def pubspec(self, version: str) -> None:
        (self.app / "pubspec.yaml").write_text(f"name: zapzap\nversion: {version}\n", encoding="utf-8")

    def build(self, *, code: int = 1, target: int = 36, internet: bool = True, page: int = 16384,
              key: str | None = "upload", alias: str = "zapzap-upload") -> None:
        # The merged manifest first, the bundle after: the script wants it no older than
        # pubspec.yaml and no newer than the bundle.
        time.sleep(0.01)
        manifest = self.root / MANIFEST_REL
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(
            f'<manifest android:versionCode="{code}" package="com.zapzap.app">'
            f'<uses-sdk android:minSdkVersion="24" android:targetSdkVersion="{target}"/></manifest>\n',
            encoding="utf-8",
        )
        time.sleep(0.01)
        self.aab.parent.mkdir(parents=True, exist_ok=True)
        permission = b"android.permission.INTERNET" if internet else b"android.permission.VIBRATE"
        with zipfile.ZipFile(self.aab, "w") as z:
            z.writestr("base/manifest/AndroidManifest.xml", b"\x0a\x02" + permission + b"\x00")
            z.write(self.libs[page], "base/lib/arm64-v8a/libapp.so")
            z.write(self.libs[16384], "base/lib/x86_64/libapp.so")
            z.write(self.libs[4096], "base/lib/armeabi-v7a/libapp.so")  # 32-bit: exempt
        if key:
            subprocess.run(
                ["jarsigner", "-keystore", str(self.keys[key]), "-storepass", PASSWORD,
                 "-keypass", PASSWORD, str(self.aab), alias],
                check=True, capture_output=True,
            )

    def verify(self) -> subprocess.CompletedProcess[str]:
        env = {**os.environ, "VERIFY_AAB_ROOT": str(self.root)}
        return subprocess.run([str(SCRIPT)], env=env, capture_output=True, text=True)


@pytest.fixture
def repo(tmp_path: Path, keys: dict[str, Path], libs: dict[int, Path]) -> Repo:
    return Repo(tmp_path, keys, libs)


def refused(result: subprocess.CompletedProcess[str], message: str) -> None:
    assert result.returncode != 0, result.stdout
    assert message in result.stderr, result.stderr
    assert "All checks passed" not in result.stdout


def test_a_good_bundle_passes(repo: Repo) -> None:
    repo.build()
    result = repo.verify()
    assert result.returncode == 0, result.stderr
    assert "OK    signed with the upload key (CN=ZapZap Upload, O=ZapZap)" in result.stdout
    assert "OK    versionCode 1 (pubspec.yaml 1.0.0+1)" in result.stdout
    assert "OK    targetSdk 36" in result.stdout
    assert "16 KB page size: 2 64-bit libraries" in result.stdout
    assert result.stdout.rstrip().endswith("All checks passed.")
    assert PASSWORD not in result.stdout + result.stderr


def test_a_debug_signed_bundle_is_refused(repo: Repo) -> None:
    repo.build(key="debug", alias="androiddebugkey")
    refused(repo.verify(), "signed with the DEBUG key")


def test_a_bundle_signed_by_another_key_is_refused(repo: Repo) -> None:
    repo.build(key="other", alias="someone")
    refused(repo.verify(), "is not the upload key")


def test_an_unsigned_bundle_is_refused(repo: Repo) -> None:
    repo.build(key=None)
    refused(repo.verify(), "not signed")


def test_no_bundle(repo: Repo) -> None:
    refused(repo.verify(), "no bundle at")


def test_no_key_properties(repo: Repo) -> None:
    repo.build()
    (repo.app / "android" / "key.properties").unlink()
    refused(repo.verify(), "key.properties missing")


def test_a_bundle_without_internet_is_refused(repo: Repo) -> None:
    repo.build(internet=False)
    refused(repo.verify(), "does not declare INTERNET")


def test_a_version_code_other_than_pubspec_is_refused(repo: Repo) -> None:
    repo.build(code=2)
    refused(repo.verify(), "versionCode 2 does not match pubspec.yaml build number 1")


def test_a_target_sdk_below_36_is_refused(repo: Repo) -> None:
    repo.build(target=35)
    refused(repo.verify(), "targetSdk 35 < 36")


def test_a_4k_aligned_library_is_refused(repo: Repo) -> None:
    repo.build(page=4096)
    refused(repo.verify(), "arm64-v8a/libapp.so has a LOAD segment aligned to")


def test_a_manifest_older_than_pubspec_is_refused(repo: Repo) -> None:
    repo.build()
    time.sleep(0.01)
    repo.pubspec("1.0.0+1")  # touched after the build: the bundle may not carry it
    refused(repo.verify(), "stale")
