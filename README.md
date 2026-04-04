# ベランダ向けリアルタイムAI監視カメラシステム

Wi-Fi接続カメラとOSSを組み合わせた、ローカルファーストなベランダ監視システムです。
クラウド不要でプライバシーを守りながら、人・鳥・猫・犬などをリアルタイム検知します。

## 実行環境別の構成

| レベル | 実行環境 | ディレクトリ | 主な技術 |
|--------|----------|------------|---------|
| Level 1 | Raspberry Pi | [`raspberry-pi/`](./raspberry-pi/) | Frigate + go2rtc（CPU推論） |
| Level 2 | スマートフォン | [`mobile/`](./mobile/) | Flutter + MediaPipe（on-device推論） |
| Level 3 | ノートPC | [`laptop/`](./laptop/) | Frigate + OpenVINO / ONNX Runtime |

> **Level 4（ゲーミングPC）**: YOLO追加学習・TensorRT化は別途実施予定

## システム構成

```
[Wi-Fi カメラ（RTSP/ONVIF）]
        ↓
   [go2rtc]  ← ストリーム中継・HLS/WebRTC変換
        ↓
   [Frigate] ← 物体検知・録画・イベント管理・UI
        ↓
[通知 / スナップショット / 録画保存]
        ↓
[Flutter スマホアプリ] ← ライブ映像・イベント確認・on-device推論
```

## 検知対象クラス

- `person`（人）
- `bird`（鳥）
- `cat`（猫）
- `dog`（犬）

## クイックスタート

### Raspberry Pi（Level 1）

```bash
cd raspberry-pi
cp .env.example .env
# .env を編集してカメラURLなどを設定
docker compose up -d
```

→ `http://<ラズパイのIP>:5000` でFrigate UIを確認

### ノートPC（Level 3）

```bash
cd laptop
cp .env.example .env
docker compose up -d
```

### スマホアプリ（Level 2）

```bash
cd mobile/balcony_guard_app
flutter pub get
flutter run
```

## セキュリティ

本システムは以下のセキュリティ要件を満たす構成を採用しています。

- **Takumi Guard**（GMO Flatt Security）によるサプライチェーン保護
  パッケージインストール前に悪意あるパッケージを自動ブロック
  詳細: https://flatt.tech/takumi/features/guard

- 資格情報は `.env` ファイルで管理（Git管理外）
- Frigate UI認証を有効化
- 原則LAN内のみ公開（外部アクセスはVPN/ゼロトラスト経由）

## カメラ要件

| 要件 | 詳細 |
|------|------|
| 接続方式 | Wi-Fi |
| 映像取得 | RTSP または ONVIF Profile S |
| コーデック | H.264（必須）、H.265（任意） |
| 解像度 | メイン 1080p 以上、サブ 720p / 5fps |
| 夜間撮影 | 対応必須 |
| 防水 | 防滴・防塵（ベランダ設置） |
| 給電 | AC常時給電推奨 |

## 参考リンク

- [Frigate ドキュメント](https://docs.frigate.video/)
- [go2rtc GitHub](https://github.com/AlexxIT/go2rtc)
- [MediaPipe Tasks](https://ai.google.dev/edge/mediapipe/solutions/guide)
- [Takumi Guard](https://flatt.tech/takumi/features/guard)
