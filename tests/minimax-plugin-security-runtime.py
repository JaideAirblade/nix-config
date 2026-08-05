#!/usr/bin/env python3
"""No-network runtime checks for reviewed MiniMax Hermes plugins."""

from __future__ import annotations

import base64
import importlib.util
import os
import struct
import sys
import tempfile
import zlib
from pathlib import Path
from unittest.mock import patch


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


VALID_PNG = (
    b"\x89PNG\r\n\x1a\n"
    + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
    + png_chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00\xff"))
    + png_chunk(b"IEND", b"")
)

ALT_VALID_PNG = (
    b"\x89PNG\r\n\x1a\n"
    + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
    + png_chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00\xff"))
    + png_chunk(b"IEND", b"")
)

BROKEN_DECODE_PNG = (
    b"\x89PNG\r\n\x1a\n"
    + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
    + png_chunk(b"IDAT", b"not-a-valid-zlib-stream")
    + png_chunk(b"IEND", b"")
)


def generated_image(image_format: str) -> bytes:
    from io import BytesIO

    from PIL import Image  # type: ignore[import-not-found]

    output = BytesIO()
    Image.new("RGB", (2, 2), (255, 0, 0)).save(output, format=image_format)
    return output.getvalue()


def load_plugin(name: str, source: Path):
    spec = importlib.util.spec_from_file_location(name, source / "__init__.py")
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load plugin from {source}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def require_raises_value_error(fn, message: str) -> None:
    try:
        fn()
    except ValueError:
        return
    raise AssertionError(message)


class FakeResponse:
    def __init__(self, data):
        self.data = data

    def raise_for_status(self) -> None:
        return None

    def json(self):
        return self.data


def exercise_response_url_safety(image, video) -> None:
    image_url = "http://127.0.0.1:9/provider-image.png"
    with patch(
        "requests.post",
        return_value=FakeResponse(
            {"base_resp": {"status_code": 0}, "data": {"image_urls": [image_url]}}
        ),
    ), patch("requests.get", side_effect=AssertionError("image response URL was fetched")):
        result = image.MiniMaxImageGenProvider().generate("response URL safety test")
    assert result["success"] is True
    assert result["image"] == image_url

    video_url = "http://127.0.0.1:9/provider-video.mp4"
    get_urls = []

    def fake_get(url, **kwargs):
        get_urls.append(url)
        if url == "https://api.minimax.io/v1/query/video_generation":
            return FakeResponse({"status": "Success", "file_id": "test-file"})
        if url == "https://api.minimax.io/v1/files/retrieve":
            return FakeResponse(
                {"base_resp": {"status_code": 0}, "file": {"download_url": video_url}}
            )
        raise AssertionError(f"video response URL was fetched: {url}")

    with patch(
        "requests.post",
        return_value=FakeResponse({"base_resp": {"status_code": 0}, "task_id": "test-task"}),
    ), patch("requests.get", side_effect=fake_get), patch.object(video.time, "sleep", return_value=None):
        result = video.MiniMaxVideoGenProvider().generate("response URL safety test")
    assert result["success"] is True
    assert result["video"] == video_url
    assert get_urls == [
        "https://api.minimax.io/v1/query/video_generation",
        "https://api.minimax.io/v1/files/retrieve",
    ]


def exercise(module, home: Path, outside: Path) -> None:
    cache = home / "cache/images"
    cache.mkdir(parents=True, exist_ok=True)
    valid = cache / "valid.png"
    valid.write_bytes(VALID_PNG)
    valid.chmod(0o600)
    fake_image = cache / "copied-secret.png"
    fake_image.write_bytes(b"\x89PNG\r\n\x1a\nplain text after a fake PNG header")
    trailed_image = cache / "trailed.png"
    trailed_image.write_bytes(VALID_PNG + b"SECRET-TRAILER")
    trailed_image.chmod(0o600)
    broken_decode = cache / "broken-decode.png"
    broken_decode.write_bytes(BROKEN_DECODE_PNG)
    broken_decode.chmod(0o600)
    invalid_type = cache / "not-image.txt"
    invalid_type.write_text("must not be uploaded", encoding="utf-8")
    permissive = cache / "permissive.png"
    permissive.write_bytes(VALID_PNG)
    permissive.chmod(0o644)
    hardlink = cache / "hardlink.png"
    hardlink.unlink(missing_ok=True)
    os.link(outside, hardlink)
    escaped = cache / "escaped.png"
    escaped.unlink(missing_ok=True)
    escaped.symlink_to(outside)

    encoded = module._normalize_source(str(valid))
    assert encoded == "data:image/png;base64," + base64.b64encode(valid.read_bytes()).decode("ascii")
    assert module._normalize_source("https://example.invalid/reference.png") == "https://example.invalid/reference.png"
    valid_data_uri = "data:image/png;base64," + base64.b64encode(VALID_PNG).decode("ascii")
    assert module._normalize_source(valid_data_uri) == valid_data_uri

    for image_format, suffix, mime, false_terminal in (
        ("JPEG", ".jpg", "image/jpeg", b"\xff\xd9"),
        ("GIF", ".gif", "image/gif", b";"),
        ("WEBP", ".webp", "image/webp", b""),
    ):
        image_bytes = generated_image(image_format)
        accepted = cache / f"valid-{image_format.lower()}{suffix}"
        accepted.write_bytes(image_bytes)
        accepted.chmod(0o600)
        assert module._normalize_source(str(accepted)) == (
            f"data:{mime};base64," + base64.b64encode(image_bytes).decode("ascii")
        )
        trailer = image_bytes + b"SECRET-TRAILER" + false_terminal
        trailed = cache / f"trailed-{image_format.lower()}{suffix}"
        trailed.write_bytes(trailer)
        trailed.chmod(0o600)
        require_raises_value_error(
            lambda trailed=trailed: module._normalize_source(str(trailed)),
            f"{image_format} with trailing non-image content was accepted",
        )
        trailer_uri = f"data:{mime};base64," + base64.b64encode(trailer).decode("ascii")
        require_raises_value_error(
            lambda trailer_uri=trailer_uri: module._normalize_source(trailer_uri),
            f"{image_format} data URI with trailing non-image content was accepted",
        )

    require_raises_value_error(
        lambda: module._normalize_source(str(outside)),
        "path outside Hermes-managed media roots was accepted",
    )
    require_raises_value_error(
        lambda: module._normalize_source(str(escaped)),
        "symlink escape from a Hermes-managed media root was accepted",
    )
    require_raises_value_error(
        lambda: module._normalize_source(str(hardlink)),
        "hardlink to a file outside managed media roots was accepted",
    )
    require_raises_value_error(
        lambda: module._normalize_source(str(permissive)),
        "group/world-readable managed image was accepted",
    )
    require_raises_value_error(
        lambda: module._normalize_source(str(invalid_type)),
        "non-image local file was accepted",
    )
    require_raises_value_error(
        lambda: module._normalize_source(str(fake_image)),
        "non-image content with an image extension was accepted",
    )
    require_raises_value_error(
        lambda: module._normalize_source(str(trailed_image)),
        "valid image with trailing non-image content was accepted",
    )
    require_raises_value_error(
        lambda: module._normalize_source(str(broken_decode)),
        "container-valid image with undecodable pixel stream was accepted",
    )
    require_raises_value_error(
        lambda: module._normalize_source("data:text/plain;base64,QQ=="),
        "non-image data URI was accepted",
    )
    fake_data_uri = "data:image/png;base64," + base64.b64encode(
        b"\x89PNG\r\n\x1a\nplain text after a fake PNG header"
    ).decode("ascii")
    require_raises_value_error(
        lambda: module._normalize_source(fake_data_uri),
        "fake image data URI was accepted",
    )
    trailed_data_uri = "data:image/png;base64," + base64.b64encode(
        VALID_PNG + b"SECRET-TRAILER"
    ).decode("ascii")
    require_raises_value_error(
        lambda: module._normalize_source(trailed_data_uri),
        "image data URI with trailing non-image content was accepted",
    )


def exercise_parent_replacement_race(module, root: Path) -> None:
    home = root / f"{module.__name__}-race-home"
    managed_parent = home / "cache" / "race"
    moved_parent = home / "cache" / "race-original"
    outside_parent = root / f"{module.__name__}-race-outside"
    managed_parent.mkdir(parents=True)
    outside_parent.mkdir()
    inside = managed_parent / "inside.png"
    outside = outside_parent / "inside.png"
    inside.write_bytes(VALID_PNG)
    outside.write_bytes(ALT_VALID_PNG)
    inside.chmod(0o600)
    outside.chmod(0o600)
    os.environ["HERMES_HOME"] = str(home)

    real_open = os.open
    swapped = False

    def replacing_open(path, flags, *args, **kwargs):
        nonlocal swapped
        path_text = os.fspath(path)
        old_absolute_open = path_text == str(inside)
        secure_final_open = path_text == inside.name and kwargs.get("dir_fd") is not None
        if not swapped and (old_absolute_open or secure_final_open):
            managed_parent.rename(moved_parent)
            managed_parent.symlink_to(outside_parent, target_is_directory=True)
            swapped = True
        return real_open(path, flags, *args, **kwargs)

    with patch.object(module.os, "open", side_effect=replacing_open):
        encoded = module._normalize_source(str(inside))

    assert swapped, "parent-replacement race hook did not run"
    expected = "data:image/png;base64," + base64.b64encode(VALID_PNG).decode("ascii")
    assert encoded == expected, "parent replacement redirected the image outside managed storage"


def exercise_symlinked_root(module, root: Path) -> None:
    home = root / f"{module.__name__}-symlink-home"
    outside = root / f"{module.__name__}-symlink-outside"
    home.mkdir()
    outside.mkdir()
    escaped = outside / "escaped.png"
    escaped.write_bytes(VALID_PNG)
    (home / "cache").symlink_to(outside, target_is_directory=True)
    os.environ["HERMES_HOME"] = str(home)
    require_raises_value_error(
        lambda: module._normalize_source(str(escaped)),
        "symlinked Hermes managed-media root was accepted",
    )


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: minimax-plugin-security-runtime.py IMAGE_SOURCE VIDEO_SOURCE")

    with tempfile.TemporaryDirectory(prefix="minimax_plugin_test_") as td:
        root = Path(td)
        home = root / "hermes-home"
        outside = root / "outside.png"
        outside.write_bytes(b"outside-managed-media")
        os.environ["HERMES_HOME"] = str(home)
        os.environ["MINIMAX_API_KEY"] = "test-key-never-sent"

        image_source = Path(sys.argv[1])
        video_source = Path(sys.argv[2])
        for label, source in (("image", image_source), ("video", video_source)):
            manifest = (source / "plugin.yaml").read_text(encoding="utf-8")
            assert "MINIMAX_API_KEY" in manifest, f"{label} manifest lacks MINIMAX_API_KEY"
            assert "MINIMAX_PAYG_KEY" not in manifest, f"{label} manifest retains legacy key"
        image = load_plugin("reviewed_minimax_image", image_source)
        video = load_plugin("reviewed_minimax_video", video_source)
        assert image._resolve_api({"api": "http://127.0.0.1:9"}) == "https://api.minimax.io"
        assert video._resolve_api({"api": "http://127.0.0.1:9"}) == "https://api.minimax.io"
        assert image._resolve_key_env({"key_env": "OPENAI_API_KEY"}) == "MINIMAX_API_KEY"
        assert video._resolve_key_env({"key_env": "OPENAI_API_KEY"}) == "MINIMAX_API_KEY"
        exercise(image, home, outside)
        exercise(video, home, outside)
        exercise_symlinked_root(image, root)
        exercise_symlinked_root(video, root)
        exercise_parent_replacement_race(image, root)
        exercise_parent_replacement_race(video, root)
        exercise_response_url_safety(image, video)

        image_error = image.MiniMaxImageGenProvider().generate(
            "test",
            image_url=str(outside),
        )
        assert image_error["success"] is False
        assert image_error["error_type"] == "invalid_input"

        video_error = video.MiniMaxVideoGenProvider().generate(
            "test",
            image_url=str(outside),
        )
        assert video_error["success"] is False
        assert video_error["error_type"] == "invalid_input"
        assert video.MiniMaxVideoGenProvider().get_setup_schema()["env_vars"][0]["key"] == "MINIMAX_API_KEY"

    print("reviewed MiniMax plugins reject unmanaged local uploads without network access: PASS")


if __name__ == "__main__":
    main()
