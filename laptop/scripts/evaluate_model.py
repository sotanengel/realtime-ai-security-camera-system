#!/usr/bin/env python3
"""
evaluate_model.py
ONNX モデルを使ってベランダ監視の検知性能（Precision / Recall / F1 / レイテンシ）を評価する。

使用方法:
    python evaluate_model.py \
        --model path/to/model.onnx \
        --data   path/to/training_data \
        --conf   0.5
"""

import argparse
import time
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort
from sklearn.metrics import classification_report, precision_recall_fscore_support
from tqdm import tqdm


# ベランダ監視で使用するクラス
CLASS_NAMES = ["person", "bird", "cat", "dog"]
CLASS_IDS = [0, 14, 15, 16]  # COCO クラスID
COCO_TO_LOCAL = {cid: i for i, cid in enumerate(CLASS_IDS)}


def load_onnx_session(model_path: str) -> ort.InferenceSession:
    """ONNX Runtimeセッションを初期化する。CPUプロバイダーを使用。"""
    providers = ["CPUExecutionProvider"]
    session = ort.InferenceSession(model_path, providers=providers)
    print(f"[INFO] モデル読み込み完了: {model_path}")
    print(f"[INFO] 入力: {session.get_inputs()[0].name} {session.get_inputs()[0].shape}")
    return session


def preprocess(image: np.ndarray, input_size: tuple[int, int] = (300, 300)) -> np.ndarray:
    """画像をモデル入力形式に変換する（SSD MobileNet v2 想定）。"""
    img = cv2.resize(image, input_size)
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    img = img.astype(np.float32)
    img = np.expand_dims(img, axis=0)
    return img


def run_inference(
    session: ort.InferenceSession, img: np.ndarray
) -> tuple[np.ndarray, np.ndarray, np.ndarray, int]:
    """推論を実行し、検出ボックス・クラス・スコアを返す。"""
    input_name = session.get_inputs()[0].name
    outputs = session.run(None, {input_name: img})

    if len(outputs) == 4:
        # SSD形式: [boxes, classes, scores, num_detections]
        boxes = outputs[0][0]
        classes = outputs[1][0].astype(int)
        scores = outputs[2][0]
        num_det = int(outputs[3][0])
    else:
        # YOLOv8 ONNX 形式（[1, 84, 8400]）
        raw = outputs[0][0].T  # (8400, 84)
        scores_all = raw[:, 4:]
        class_ids = np.argmax(scores_all, axis=1)
        scores = np.max(scores_all, axis=1)
        boxes = raw[:, :4]
        classes = class_ids
        num_det = len(classes)

    return boxes, classes, scores, num_det


def load_ground_truth(label_path: Path) -> list[int]:
    """YOLO形式のアノテーションファイルからクラスIDを読み込む。"""
    if not label_path.exists():
        return []
    lines = label_path.read_text().strip().splitlines()
    class_ids = []
    for line in lines:
        parts = line.strip().split()
        if parts:
            coco_id = int(parts[0])
            local_id = COCO_TO_LOCAL.get(coco_id, -1)
            if local_id >= 0:
                class_ids.append(local_id)
    return class_ids


def evaluate(
    session: ort.InferenceSession,
    data_dir: Path,
    conf_threshold: float,
    input_size: tuple[int, int],
) -> None:
    """評価を実行して Precision / Recall / F1 / レイテンシを出力する。"""
    images_dir = data_dir / "images"
    labels_dir = data_dir / "labels"
    image_paths = sorted(images_dir.glob("*.jpg"))

    if not image_paths:
        print(f"[ERROR] 画像が見つかりません: {images_dir}")
        return

    y_true: list[int] = []
    y_pred: list[int] = []
    latencies: list[float] = []

    for img_path in tqdm(image_paths, desc="評価中"):
        image = cv2.imread(str(img_path))
        if image is None:
            continue

        gt_classes = load_ground_truth(labels_dir / img_path.with_suffix(".txt").name)

        inp = preprocess(image, input_size)
        t0 = time.perf_counter()
        boxes, classes, scores, num_det = run_inference(session, inp)
        latency_ms = (time.perf_counter() - t0) * 1000
        latencies.append(latency_ms)

        pred_classes: list[int] = []
        for i in range(min(num_det, len(scores))):
            if scores[i] < conf_threshold:
                continue
            local_id = COCO_TO_LOCAL.get(int(classes[i]), -1)
            if local_id >= 0:
                pred_classes.append(local_id)

        # 1画像につき1クラスの判定（最高スコアクラス）
        if gt_classes:
            gt_label = gt_classes[0]
        else:
            gt_label = -1  # 背景

        pred_label = pred_classes[0] if pred_classes else -1

        if gt_label >= 0 or pred_label >= 0:
            y_true.append(max(gt_label, 0))
            y_pred.append(max(pred_label, 0))

    print("\n" + "=" * 60)
    print("検知性能評価レポート")
    print("=" * 60)
    print(classification_report(
        y_true, y_pred,
        labels=list(range(len(CLASS_NAMES))),
        target_names=CLASS_NAMES,
        zero_division=0,
    ))

    p, r, f1, _ = precision_recall_fscore_support(
        y_true, y_pred,
        average="macro",
        zero_division=0,
    )
    print(f"マクロ平均   Precision: {p:.3f}  Recall: {r:.3f}  F1: {f1:.3f}")

    if latencies:
        avg_ms = np.mean(latencies)
        p50 = np.percentile(latencies, 50)
        p95 = np.percentile(latencies, 95)
        print(f"\n推論レイテンシ  平均: {avg_ms:.1f}ms  P50: {p50:.1f}ms  P95: {p95:.1f}ms")
        print(f"評価画像数: {len(latencies)}")
    print("=" * 60)


def main() -> None:
    parser = argparse.ArgumentParser(description="ONNXモデルの検知性能を評価する")
    parser.add_argument("--model", required=True, help="ONNXモデルファイルパス")
    parser.add_argument(
        "--data", default="./training_data", help="学習データディレクトリ（images/, labels/ を含む）"
    )
    parser.add_argument("--conf", type=float, default=0.5, help="信頼度しきい値")
    parser.add_argument(
        "--input-size",
        type=int,
        nargs=2,
        default=[300, 300],
        metavar=("W", "H"),
        help="モデル入力解像度（デフォルト: 300 300）",
    )
    args = parser.parse_args()

    session = load_onnx_session(args.model)
    evaluate(
        session,
        Path(args.data),
        conf_threshold=args.conf,
        input_size=tuple(args.input_size),  # type: ignore[arg-type]
    )


if __name__ == "__main__":
    main()
