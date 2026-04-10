"""collect_video_samples のユニットテスト。

動画ファイル・ONNXモデルを使わず、関数単位でロジックを検証する。
"""

import json
from pathlib import Path

from balcony_guard.collect_video_samples import (
    CLASS_IDS,
    CLASS_NAMES,
    COCO_TO_LOCAL,
    LABEL_TO_CLASS_ID,
    VIDEO_EXTENSIONS,
    find_video_files,
    generate_dataset_yaml,
    save_metadata,
)


class TestConstants:
    def test_class_mapping_consistent(self) -> None:
        """クラスマッピングが collect_training_samples.py と一致すること。"""
        assert LABEL_TO_CLASS_ID == {"person": 0, "bird": 14, "cat": 15, "dog": 16}

    def test_class_names_order(self) -> None:
        assert CLASS_NAMES == ["person", "bird", "cat", "dog"]

    def test_coco_to_local_mapping(self) -> None:
        assert COCO_TO_LOCAL == {0: 0, 14: 1, 15: 2, 16: 3}

    def test_class_ids_match_label_values(self) -> None:
        assert list(LABEL_TO_CLASS_ID.values()) == CLASS_IDS


class TestFindVideoFiles:
    def test_single_mp4_file(self, tmp_path: Path) -> None:
        video = tmp_path / "test.mp4"
        video.touch()
        result = find_video_files(video)
        assert result == [video]

    def test_single_mov_file(self, tmp_path: Path) -> None:
        video = tmp_path / "test.MOV"
        video.touch()
        result = find_video_files(video)
        assert result == [video]

    def test_non_video_file_ignored(self, tmp_path: Path) -> None:
        txt = tmp_path / "test.txt"
        txt.touch()
        result = find_video_files(txt)
        assert result == []

    def test_directory_with_videos(self, tmp_path: Path) -> None:
        (tmp_path / "a.mp4").touch()
        (tmp_path / "b.mov").touch()
        (tmp_path / "c.txt").touch()
        result = find_video_files(tmp_path)
        names = {p.name for p in result}
        assert "a.mp4" in names
        assert "b.mov" in names
        assert "c.txt" not in names

    def test_empty_directory(self, tmp_path: Path) -> None:
        result = find_video_files(tmp_path)
        assert result == []

    def test_supported_extensions(self) -> None:
        assert ".mp4" in VIDEO_EXTENSIONS
        assert ".mov" in VIDEO_EXTENSIONS
        assert ".avi" in VIDEO_EXTENSIONS


class TestGenerateDatasetYaml:
    def test_creates_yaml(self, tmp_path: Path) -> None:
        generate_dataset_yaml(tmp_path)
        yaml_path = tmp_path / "dataset.yaml"
        assert yaml_path.exists()
        content = yaml_path.read_text()
        assert "train: images" in content
        assert "val: images" in content
        assert "nc: 4" in content
        assert "person" in content


class TestSaveMetadata:
    def test_saves_json_files(self, tmp_path: Path) -> None:
        frames = [
            {
                "frame_id": "test_000001",
                "video_file": "test.mp4",
                "frame_index": 30,
                "timestamp_sec": 1.0,
                "width": 1920,
                "height": 1080,
            },
        ]
        save_metadata(tmp_path, frames, Path("test.mp4"))

        meta_path = tmp_path / "metadata" / "test_000001.json"
        assert meta_path.exists()

        data = json.loads(meta_path.read_text())
        assert data["source"] == "smartphone_video"
        assert data["video_file"] == "test.mp4"
        assert data["frame_index"] == 30
        assert data["width"] == 1920
