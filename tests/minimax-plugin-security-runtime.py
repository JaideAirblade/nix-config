#!/usr/bin/env python3
"""No-network runtime checks for reviewed MiniMax Hermes plugins."""

from __future__ import annotations

import base64
import importlib.util
import os
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch


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
    valid.write_bytes(b"\x89PNG\r\n\x1a\nnot-secret-test-image-bytes")
    fake_image = cache / "copied-secret.png"
    fake_image.write_bytes(b"plain text copied into an image-looking filename")
    invalid_type = cache / "not-image.txt"
    invalid_type.write_text("must not be uploaded", encoding="utf-8")
    hardlink = cache / "hardlink.png"
    hardlink.unlink(missing_ok=True)
    os.link(outside, hardlink)
    escaped = cache / "escaped.png"
    escaped.unlink(missing_ok=True)
    escaped.symlink_to(outside)

    encoded = module._normalize_source(str(valid))
    assert encoded == "data:image/png;base64," + base64.b64encode(valid.read_bytes()).decode("ascii")
    assert module._normalize_source("https://example.invalid/reference.png") == "https://example.invalid/reference.png"
    assert module._normalize_source("data:image/png;base64,AA==") == "data:image/png;base64,AA=="

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
        lambda: module._normalize_source(str(invalid_type)),
        "non-image local file was accepted",
    )
    require_raises_value_error(
        lambda: module._normalize_source(str(fake_image)),
        "non-image content with an image extension was accepted",
    )
    require_raises_value_error(
        lambda: module._normalize_source("data:text/plain;base64,QQ=="),
        "non-image data URI was accepted",
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

        image = load_plugin("reviewed_minimax_image", Path(sys.argv[1]))
        video = load_plugin("reviewed_minimax_video", Path(sys.argv[2]))
        assert image._resolve_api({"api": "http://127.0.0.1:9"}) == "https://api.minimax.io"
        assert video._resolve_api({"api": "http://127.0.0.1:9"}) == "https://api.minimax.io"
        assert image._resolve_key_env({"key_env": "OPENAI_API_KEY"}) == "MINIMAX_API_KEY"
        assert video._resolve_key_env({"key_env": "OPENAI_API_KEY"}) == "MINIMAX_API_KEY"
        exercise(image, home, outside)
        exercise(video, home, outside)
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
