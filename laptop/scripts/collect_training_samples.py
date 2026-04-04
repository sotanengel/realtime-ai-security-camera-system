#!/usr/bin/env python3
"""
collect_training_samples.py
Frigate Events APIから誤検知・見逃し候補のスナップショットを収集し、
YOLO形式の学習データとして保存するスクリプト。

使用方法:
    python collect_training_samples.py --host http://localhost:5000 --output ./training_data
"""

import argparse
import json
import time
from pathlib import Path


def get_events(
    host: str,
    camera: str | None = None,
    label: str | None = None,
    limit: int = 100,
    after: float | None = None,
    before: float | None = None,
    has_snapshot: bool = True,
) -> list[dict]:
    """Frigate Events APIからイベント一覧を取得する。"""
    import requests  # noqa: PLC0415

    params: dict = {"limit": limit, "has_snapshot": int(has_snapshot)}
    if camera:
        params["camera"] = camera
    if label:
        params["label"] = label
    if after:
        params["after"] = after
    if before:
        params["before"] = before

    resp = requests.get(f"{host}/api/events", params=params, timeout=30)
    resp.raise_for_status()
    return resp.json()


def download_snapshot(host: str, event_id: str, dest_path: Path) -> bool:
    """イベントのスナップショット画像をダウンロードする。"""
    import requests  # noqa: PLC0415

    url = f"{host}/api/events/{event_id}/snapshot.jpg"
    try:
        resp = requests.get(url, timeout=30)
        resp.raise_for_status()
        dest_path.write_bytes(resp.content)
        return True
    except requests.RequestException as e:
        print(f"  [WARN] スナップショット取得失敗 {event_id}: {e}")
        return False


def download_thumbnail(host: str, event_id: str, dest_path: Path) -> bool:
    """イベントのサムネイル画像をダウンロードする。"""
    import requests  # noqa: PLC0415

    url = f"{host}/api/events/{event_id}/thumbnail.jpg"
    try:
        resp = requests.get(url, timeout=30)
        resp.raise_for_status()
        dest_path.write_bytes(resp.content)
        return True
    except requests.RequestException as e:
        print(f"  [WARN] サムネイル取得失敗 {event_id}: {e}")
        return False


def bbox_to_yolo(
    box: dict, img_width: int = 1280, img_height: int = 720
) -> tuple[float, float, float, float]:
    """
    Frigateのバウンディングボックス（[x_min, y_min, x_max, y_max]）を
    YOLO形式（x_center, y_center, width, height）に変換する。
    値は画像サイズに対する相対値（0.0〜1.0）。
    """
    x_min, y_min, x_max, y_max = box
    x_center = (x_min + x_max) / 2 / img_width
    y_center = (y_min + y_max) / 2 / img_height
    width = (x_max - x_min) / img_width
    height = (y_max - y_min) / img_height
    return x_center, y_center, width, height


# COCOクラスIDのマッピング（FrigateのデフォルトCOCOラベル → YOLO クラスID）
LABEL_TO_CLASS_ID = {
    "person": 0,
    "bird": 14,
    "cat": 15,
    "dog": 16,
}


def save_yolo_label(
    dest_path: Path, label: str, box: list, img_width: int = 1280, img_height: int = 720
) -> None:
    """YOLO形式のアノテーションファイルを保存する。"""
    class_id = LABEL_TO_CLASS_ID.get(label, -1)
    if class_id < 0:
        return
    x_c, y_c, w, h = bbox_to_yolo(box, img_width, img_height)
    dest_path.write_text(f"{class_id} {x_c:.6f} {y_c:.6f} {w:.6f} {h:.6f}\n")


def save_metadata(dest_path: Path, event: dict) -> None:
    """イベントメタデータをJSONで保存する（D-004）。"""
    metadata = {
        "event_id": event.get("id"),
        "camera": event.get("camera"),
        "label": event.get("label"),
        "score": event.get("score"),
        "start_time": event.get("start_time"),
        "end_time": event.get("end_time"),
        "box": event.get("box"),
        "area": event.get("area"),
        "zone": event.get("current_zones"),
    }
    dest_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2))


def collect_samples(
    host: str,
    output_dir: Path,
    labels: list[str],
    camera: str | None,
    limit: int,
    after: float | None,
    before: float | None,
) -> None:
    """メイン収集処理。"""
    from tqdm import tqdm  # noqa: PLC0415

    output_dir.mkdir(parents=True, exist_ok=True)
    images_dir = output_dir / "images"
    labels_dir = output_dir / "labels"
    metadata_dir = output_dir / "metadata"
    images_dir.mkdir(exist_ok=True)
    labels_dir.mkdir(exist_ok=True)
    metadata_dir.mkdir(exist_ok=True)

    total_saved = 0
    for label in labels:
        print(f"\n[INFO] 収集中: label={label}")
        events = get_events(
            host,
            camera=camera,
            label=label,
            limit=limit,
            after=after,
            before=before,
        )
        print(f"  取得イベント数: {len(events)}")

        for event in tqdm(events, desc=f"  {label}"):
            event_id = event.get("id", "")
            if not event_id:
                continue

            img_path = images_dir / f"{event_id}.jpg"
            lbl_path = labels_dir / f"{event_id}.txt"
            meta_path = metadata_dir / f"{event_id}.json"

            if img_path.exists():
                continue

            if not download_snapshot(host, event_id, img_path):
                continue

            box = event.get("box")
            if box:
                save_yolo_label(lbl_path, label, box)

            save_metadata(meta_path, event)
            total_saved += 1
            time.sleep(0.05)  # APIレート制限対策

    # YOLO dataset.yaml を生成
    yaml_path = output_dir / "dataset.yaml"
    yaml_content = (
        f"path: {output_dir.resolve()}\n"
        "train: images\n"
        "val: images\n"
        "nc: 4\n"
        "names: ['person', 'bird', 'cat', 'dog']\n"
    )
    yaml_path.write_text(yaml_content)

    print(f"\n[INFO] 完了: {total_saved} 件保存 → {output_dir}")
    print(f"[INFO] dataset.yaml: {yaml_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Frigate Events APIから学習用スナップショットを収集する"
    )
    parser.add_argument("--host", default="http://localhost:5000", help="Frigate のホストURL")
    parser.add_argument("--output", default="./training_data", help="保存先ディレクトリ")
    parser.add_argument(
        "--labels",
        nargs="+",
        default=["person", "bird", "cat", "dog"],
        help="収集するラベル（スペース区切り）",
    )
    parser.add_argument("--camera", default=None, help="対象カメラ名（省略時は全カメラ）")
    parser.add_argument("--limit", type=int, default=200, help="1ラベルあたりの最大取得件数")
    parser.add_argument("--after", type=float, default=None, help="開始日時（UNIXタイムスタンプ）")
    parser.add_argument("--before", type=float, default=None, help="終了日時（UNIXタイムスタンプ）")
    args = parser.parse_args()

    collect_samples(
        host=args.host,
        output_dir=Path(args.output),
        labels=args.labels,
        camera=args.camera,
        limit=args.limit,
        after=args.after,
        before=args.before,
    )


if __name__ == "__main__":
    main()
