#!/usr/bin/env python3
"""
collect_video_samples.py
スマートフォンで撮影した動画ファイルからフレームを抽出し、
ONNXモデルによる自動アノテーション付きYOLO形式の学習データを生成する。

使用方法:
    # 動画から1秒間隔でフレーム抽出（アノテーションなし）
    python -m balcony_guard.collect_video_samples --input video.mp4

    # ONNXモデルで自動アノテーション付き
    python -m balcony_guard.collect_video_samples \
        --input ./videos/ \
        --model model.onnx \
        --interval 0.5 \
        --conf 0.5

出力形式は collect_training_samples.py と同一のYOLO形式:
    output/
    ├── images/       # 抽出フレーム (JPEG)
    ├── labels/       # YOLOアノテーション
    ├── metadata/     # フレームメタデータ (JSON)
    └── dataset.yaml  # YOLO設定
"""

import argparse
import json
import time
from pathlib import Path

# collect_training_samples.py と同じクラスマッピングを使用
LABEL_TO_CLASS_ID = {
    "person": 0,
    "bird": 14,
    "cat": 15,
    "dog": 16,
}
CLASS_NAMES = ["person", "bird", "cat", "dog"]
CLASS_IDS = [0, 14, 15, 16]
COCO_TO_LOCAL = {cid: i for i, cid in enumerate(CLASS_IDS)}

VIDEO_EXTENSIONS = {".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v"}


def find_video_files(input_path: Path) -> list[Path]:
    """入力パスから動画ファイルを検索する。"""
    if input_path.is_file():
        if input_path.suffix.lower() in VIDEO_EXTENSIONS:
            return [input_path]
        return []
    if input_path.is_dir():
        files = []
        for ext in VIDEO_EXTENSIONS:
            files.extend(input_path.glob(f"*{ext}"))
            files.extend(input_path.glob(f"*{ext.upper()}"))
        return sorted(set(files))
    return []


def extract_frames(
    video_path: Path,
    output_dir: Path,
    interval_sec: float = 1.0,
    max_frames: int = 0,
) -> list[dict]:
    """動画からフレームを抽出し、メタデータとともに返す。"""
    import cv2  # noqa: PLC0415

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        print(f"  [ERROR] 動画を開けません: {video_path}")
        return []

    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    duration = total_frames / fps if fps > 0 else 0
    frame_interval = max(1, int(fps * interval_sec))

    print(f"  動画情報: {width}x{height}, {fps:.1f}fps, {duration:.1f}秒, {total_frames}フレーム")
    print(f"  抽出間隔: {interval_sec}秒 ({frame_interval}フレームごと)")

    images_dir = output_dir / "images"
    images_dir.mkdir(parents=True, exist_ok=True)

    extracted = []
    frame_idx = 0
    saved_count = 0
    video_name = video_path.stem

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        if frame_idx % frame_interval == 0:
            timestamp_sec = frame_idx / fps if fps > 0 else 0
            frame_id = f"{video_name}_{frame_idx:06d}"
            img_path = images_dir / f"{frame_id}.jpg"

            cv2.imwrite(str(img_path), frame, [cv2.IMWRITE_JPEG_QUALITY, 95])

            extracted.append(
                {
                    "frame_id": frame_id,
                    "video_file": video_path.name,
                    "frame_index": frame_idx,
                    "timestamp_sec": round(timestamp_sec, 3),
                    "width": width,
                    "height": height,
                    "img_path": str(img_path),
                }
            )
            saved_count += 1

            if max_frames > 0 and saved_count >= max_frames:
                break

        frame_idx += 1

    cap.release()
    print(f"  抽出完了: {saved_count}フレーム")
    return extracted


def auto_annotate(
    frames: list[dict],
    output_dir: Path,
    model_path: str,
    conf_threshold: float,
    input_size: tuple[int, int],
) -> int:
    """ONNXモデルでフレームを自動アノテーションする。"""
    import cv2  # noqa: PLC0415
    import numpy as np  # noqa: PLC0415
    import onnxruntime as ort  # noqa: PLC0415
    from tqdm import tqdm  # noqa: PLC0415

    providers = ["CPUExecutionProvider"]
    session = ort.InferenceSession(model_path, providers=providers)
    input_name = session.get_inputs()[0].name
    print(f"[INFO] モデル読み込み: {model_path}")
    print(f"[INFO] 入力サイズ: {input_size}")

    labels_dir = output_dir / "labels"
    labels_dir.mkdir(parents=True, exist_ok=True)

    annotated_count = 0

    for frame_info in tqdm(frames, desc="自動アノテーション中"):
        img = cv2.imread(frame_info["img_path"])
        if img is None:
            continue

        img_h, img_w = img.shape[:2]

        # 前処理: リサイズ → BGR→RGB → float32
        resized = cv2.resize(img, input_size)
        rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
        blob = np.expand_dims(rgb.astype(np.float32), axis=0)

        outputs = session.run(None, {input_name: blob})

        detections = _parse_detections(outputs, conf_threshold)

        if detections:
            frame_id = frame_info["frame_id"]
            label_path = labels_dir / f"{frame_id}.txt"
            lines = []
            for det in detections:
                class_id = det["class_id"]
                box = det["box"]  # [x_min, y_min, x_max, y_max] normalized
                x_center = (box[0] + box[2]) / 2
                y_center = (box[1] + box[3]) / 2
                w = box[2] - box[0]
                h = box[3] - box[1]
                lines.append(f"{class_id} {x_center:.6f} {y_center:.6f} {w:.6f} {h:.6f}")

            label_path.write_text("\n".join(lines) + "\n")
            frame_info["detections"] = [
                {"class_id": d["class_id"], "score": d["score"], "label": d["label"]}
                for d in detections
            ]
            annotated_count += 1

    return annotated_count


def _parse_detections(
    outputs: list,
    conf_threshold: float,
) -> list[dict]:
    """モデル出力を解析して検出結果を返す。SSD / YOLOv8 両形式対応。"""
    import numpy as np  # noqa: PLC0415

    detections = []

    if len(outputs) == 4:
        # SSD形式: [boxes, classes, scores, num_detections]
        boxes = outputs[0][0]
        classes = outputs[1][0].astype(int)
        scores = outputs[2][0]
        num_det = int(outputs[3][0])

        for i in range(num_det):
            if scores[i] < conf_threshold:
                continue
            coco_id = int(classes[i])
            local_idx = COCO_TO_LOCAL.get(coco_id, -1)
            if local_idx < 0:
                continue
            # SSD boxes: [y_min, x_min, y_max, x_max] normalized
            box = [
                float(boxes[i][1]),  # x_min
                float(boxes[i][0]),  # y_min
                float(boxes[i][3]),  # x_max
                float(boxes[i][2]),  # y_max
            ]
            detections.append(
                {
                    "class_id": coco_id,
                    "label": CLASS_NAMES[local_idx],
                    "score": round(float(scores[i]), 4),
                    "box": box,
                }
            )
    else:
        # YOLOv8 ONNX形式 [1, 84, 8400]
        raw = outputs[0][0].T  # (8400, 84)
        scores_all = raw[:, 4:]
        class_ids = np.argmax(scores_all, axis=1)
        max_scores = np.max(scores_all, axis=1)

        for i in range(len(class_ids)):
            if max_scores[i] < conf_threshold:
                continue
            coco_id = int(class_ids[i])
            local_idx = COCO_TO_LOCAL.get(coco_id, -1)
            if local_idx < 0:
                continue
            # YOLOv8: [cx, cy, w, h] → [x_min, y_min, x_max, y_max]
            cx, cy, w, h = raw[i, :4]
            box = [
                float(cx - w / 2),
                float(cy - h / 2),
                float(cx + w / 2),
                float(cy + h / 2),
            ]
            detections.append(
                {
                    "class_id": coco_id,
                    "label": CLASS_NAMES[local_idx],
                    "score": round(float(max_scores[i]), 4),
                    "box": box,
                }
            )

    return detections


def save_metadata(output_dir: Path, frames: list[dict], video_path: Path) -> None:
    """フレームメタデータをJSONで保存する。"""
    metadata_dir = output_dir / "metadata"
    metadata_dir.mkdir(parents=True, exist_ok=True)

    for frame_info in frames:
        frame_id = frame_info["frame_id"]
        meta = {
            "frame_id": frame_id,
            "source": "smartphone_video",
            "video_file": frame_info["video_file"],
            "frame_index": frame_info["frame_index"],
            "timestamp_sec": frame_info["timestamp_sec"],
            "width": frame_info["width"],
            "height": frame_info["height"],
            "detections": frame_info.get("detections", []),
            "extracted_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        }
        meta_path = metadata_dir / f"{frame_id}.json"
        meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2))


def generate_dataset_yaml(output_dir: Path) -> None:
    """YOLO dataset.yaml を生成する。collect_training_samples.py と同一形式。"""
    yaml_path = output_dir / "dataset.yaml"
    yaml_content = (
        f"path: {output_dir.resolve()}\n"
        "train: images\n"
        "val: images\n"
        f"nc: {len(CLASS_NAMES)}\n"
        f"names: {CLASS_NAMES}\n"
    )
    yaml_path.write_text(yaml_content)
    print(f"[INFO] dataset.yaml: {yaml_path}")


def collect_video_samples(
    input_path: Path,
    output_dir: Path,
    model_path: str | None,
    interval_sec: float,
    max_frames: int,
    conf_threshold: float,
    input_size: tuple[int, int],
) -> None:
    """メイン処理: 動画→フレーム抽出→（自動アノテーション）→YOLO形式保存。"""
    video_files = find_video_files(input_path)
    if not video_files:
        print(f"[ERROR] 動画ファイルが見つかりません: {input_path}")
        return

    print(f"[INFO] 対象動画: {len(video_files)}件")
    output_dir.mkdir(parents=True, exist_ok=True)

    all_frames: list[dict] = []
    for video_path in video_files:
        print(f"\n[INFO] 処理中: {video_path.name}")
        frames = extract_frames(video_path, output_dir, interval_sec, max_frames)
        all_frames.extend(frames)

    if not all_frames:
        print("[ERROR] フレームを抽出できませんでした")
        return

    if model_path:
        annotated = auto_annotate(all_frames, output_dir, model_path, conf_threshold, input_size)
        print(f"\n[INFO] アノテーション済み: {annotated}/{len(all_frames)}フレーム")

    for video_path in video_files:
        video_frames = [f for f in all_frames if f["video_file"] == video_path.name]
        save_metadata(output_dir, video_frames, video_path)

    generate_dataset_yaml(output_dir)

    print(f"\n[INFO] 完了: {len(all_frames)}フレーム → {output_dir}")


def main() -> None:
    parser = argparse.ArgumentParser(description="スマホ動画からYOLO形式の学習データを生成する")
    parser.add_argument(
        "--input",
        required=True,
        help="動画ファイルまたはディレクトリのパス",
    )
    parser.add_argument(
        "--output",
        default="./training_data",
        help="保存先ディレクトリ（デフォルト: ./training_data）",
    )
    parser.add_argument(
        "--model",
        default=None,
        help="自動アノテーション用ONNXモデルパス（省略時はフレーム抽出のみ）",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=1.0,
        help="フレーム抽出間隔（秒、デフォルト: 1.0）",
    )
    parser.add_argument(
        "--max-frames",
        type=int,
        default=0,
        help="動画あたりの最大抽出フレーム数（0=無制限）",
    )
    parser.add_argument(
        "--conf",
        type=float,
        default=0.5,
        help="自動アノテーションの信頼度しきい値（デフォルト: 0.5）",
    )
    parser.add_argument(
        "--input-size",
        type=int,
        nargs=2,
        default=[300, 300],
        metavar=("W", "H"),
        help="モデル入力解像度（デフォルト: 300 300）",
    )
    args = parser.parse_args()

    collect_video_samples(
        input_path=Path(args.input),
        output_dir=Path(args.output),
        model_path=args.model,
        interval_sec=args.interval,
        max_frames=args.max_frames,
        conf_threshold=args.conf,
        input_size=tuple(args.input_size),  # type: ignore[arg-type]
    )


if __name__ == "__main__":
    main()
