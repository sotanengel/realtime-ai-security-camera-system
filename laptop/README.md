# ノートPC セットアップガイド（Level 3）

録画・ゾーン調整・推論最適化の標準開発・小規模本番環境のセットアップガイドです。

## 前提条件

- Intel / AMD / Apple Silicon ノートPC
- メモリ 16GB 以上推奨
- Docker・Docker Compose インストール済み
- Python 3.11 以上（スクリプト実行用）

## セットアップ手順

### 1. Takumi Guard のセットアップ（サプライチェーンセキュリティ）

本プロジェクトでは [Takumi Guard](https://flatt.tech/takumi/features/guard) を使用して、
Pythonパッケージのサプライチェーンセキュリティを確保します。

1. Takumi のアカウント作成・Guard設定: https://flatt.tech/takumi/features/guard
2. 発行されたGuardレジストリURLを `scripts/pip.conf` の `index-url` に設定する

```ini
# scripts/pip.conf
[global]
index-url = https://guard.takumi.flatt.tech/pypi/simple/  # ← 実際のURLを設定
```

### 2. 環境変数の設定

```bash
cp .env.example .env
# .env を編集してカメラURL等を設定
```

### 3. Dockerコンテナ起動

```bash
docker compose up -d
```

ブラウザで `http://localhost:5000` を開いてFrigate UIを確認。

### 4. 推論エンジンの選択

#### Intel CPU / iGPU（OpenVINO）を使う場合

`docker-compose.yml` の `devices` セクションのコメントを外す:

```yaml
devices:
  - /dev/dri:/dev/dri
```

`config/frigate.yml` の detector を `openvino` に設定（デフォルト）。

#### Apple Silicon / その他 CPU（ONNX Runtime）を使う場合

`config/frigate.yml` の detector セクションを以下に変更:

```yaml
detectors:
  ort:
    type: onnxruntime
    device: cpu
```

### 5. Pythonスクリプトのセットアップ

```bash
cd scripts

# Takumi Guard 経由でパッケージをインストール（推奨）
pip install --config-file pip.conf -r requirements.txt

# または通常インストール
pip install -r requirements.txt
```

## 学習データ収集

誤検知・見逃し例を収集してYOLO学習データを作成します:

```bash
cd scripts

# Frigateの全イベントを収集（デフォルト: 最新200件/クラス）
python collect_training_samples.py \
    --host http://localhost:5000 \
    --output ./training_data

# 特定カメラ・期間を指定
python collect_training_samples.py \
    --host http://localhost:5000 \
    --camera balcony \
    --labels person bird \
    --limit 500
```

収集データは `training_data/` に保存されます:

```
training_data/
├── images/     # スナップショット画像
├── labels/     # YOLO形式アノテーション（.txt）
├── metadata/   # イベントメタデータ（JSON）
└── dataset.yaml
```

## モデル評価

ONNXモデルの検知性能を評価します:

```bash
cd scripts
python evaluate_model.py \
    --model path/to/model.onnx \
    --data ./training_data \
    --conf 0.5
```

出力例:
```
Precision / Recall / F1 per class
推論レイテンシ P50 / P95
```

## ゾーン・マスクの調整

1. `http://localhost:5000` → Settings → Cameras → balcony を開く
2. UIでゾーン座標を確認・調整
3. `config/frigate.yml` の `zones.balcony_interior.coordinates` を更新
4. `docker compose restart frigate` で反映

## セキュリティ設定

### LAN内制限（NF-022）

```bash
# macOS: pf でポート制限（/etc/pf.conf を編集）
# Linux: ufw でポート制限
sudo ufw allow from 192.168.0.0/16 to any port 5000
sudo ufw allow from 192.168.0.0/16 to any port 1984
sudo ufw deny 5000
sudo ufw deny 1984
```

### VPN経由外部アクセス（NF-024）

外部からのアクセスには WireGuard / Tailscale などを利用してください。

## ディレクトリ構成

```
laptop/
├── docker-compose.yml
├── config/
│   ├── frigate.yml
│   └── go2rtc.yml
├── scripts/
│   ├── requirements.txt
│   ├── pip.conf              # Takumi Guard設定
│   ├── collect_training_samples.py
│   └── evaluate_model.py
├── media/                    # 録画・スナップショット（自動生成）
├── .env
├── .env.example
└── README.md
```
