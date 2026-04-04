# Balcony Guard アプリ（Level 2: スマートフォン）

ベランダ監視補助アプリです。以下の機能を提供します。

- **ライブ映像確認**: go2rtc HLSストリームをアプリ内で表示
- **イベント一覧**: Frigate検知履歴・スナップショットの確認
- **ローカル推論**: スマホカメラを使ったon-device物体検知（MediaPipe / TFLite）
- **通知**: 検知イベントのローカル通知

## 前提条件

- Flutter SDK 3.19 以上
- iOS 14 以上 または Android 7.0 (API 24) 以上
- Frigate / go2rtc が同一LAN内で稼働していること

## セットアップ手順

### 1. Takumi Guard のセットアップ（サプライチェーンセキュリティ）

本アプリでは [Takumi Guard](https://flatt.tech/takumi/features/guard) によるサプライチェーン保護を採用しています。

Dart / Flutter パッケージの Guard 設定は公式サイトを参照してください:
https://flatt.tech/takumi/features/guard

Takumi Guard が pub レジストリプロキシを提供している場合、`pubspec.yaml` を以下のように設定します:

```yaml
# pubspec.yaml に追加（Takumi Guardドキュメントに従って設定）
# hosted:
#   url: https://guard.takumi.flatt.tech/pub/
```

または環境変数で設定:

```bash
export PUB_HOSTED_URL=https://guard.takumi.flatt.tech/pub/
flutter pub get
```

### 2. 依存パッケージのインストール

```bash
cd mobile/balcony_guard_app

# Takumi Guard経由（推奨）
PUB_HOSTED_URL=https://guard.takumi.flatt.tech/pub/ flutter pub get

# 通常インストール
flutter pub get
```

### 3. MediaPipeモデルのダウンロード

on-device推論に使用する TFLite モデルを `assets/models/` に配置してください。

```bash
# EfficientDet-Lite0 (COCO, INT8量子化) をダウンロード
cd mobile/balcony_guard_app
mkdir -p assets/models

curl -L \
  "https://storage.googleapis.com/mediapipe-models/object_detector/efficientdet_lite0/int8/1/efficientdet_lite0.tflite" \
  -o assets/models/efficientdet_lite0.tflite
```

> **Note**: モデルファイル（.tflite）は `.gitignore` でGit管理から除外されています。
> ビルド前に必ずダウンロードしてください。

### 4. Android の追加設定

`android/app/src/main/AndroidManifest.xml` に以下を追加:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

### 5. iOS の追加設定

`ios/Runner/Info.plist` に以下を追加:

```xml
<key>NSCameraUsageDescription</key>
<string>ベランダの物体検知に使用します</string>
<key>NSLocalNetworkUsageDescription</key>
<string>LAN内のFrigate/go2rtcに接続するために使用します</string>
```

### 6. ビルド・実行

```bash
# 開発モードで実行
flutter run

# iOS ビルド
flutter build ios --release

# Android ビルド
flutter build apk --release
```

## 使い方

### Frigate接続設定

アプリ起動後、ホーム画面右上の⚙️ボタンから FrigateのホストURLを設定します。

```
http://192.168.1.100:5000
```

> go2rtcは Frigateのポート (5000) から自動的にポート (1984) に変換されます。

### ライブ映像

- `balcony_sub`（低解像度・低遅延）と `balcony_main`（高解像度）を切り替えできます
- 接続失敗時は「再接続」ボタンで再試行してください

### イベント一覧

- ラベル（person / bird / cat / dog）でフィルタリングできます
- 30秒ごとに自動更新されます（手動更新: プルダウン）
- タップするとスナップショットと詳細情報を確認できます

### ローカル推論

- スマホカメラからリアルタイムで物体検知を行います
- 検知精度（信頼度しきい値）は🎛️ボタンで調整できます
- 発熱を抑えるため、3fps程度の処理頻度で動作します
- 常時給電時のみ長時間使用を推奨します（NF-032）

## アーキテクチャ

```
lib/
├── main.dart                      # エントリポイント・通知初期化
├── app.dart                       # ルーター・テーマ設定
├── models/
│   └── detection_event.dart       # Frigateイベントデータモデル
├── screens/
│   ├── home_screen.dart           # ナビゲーション・接続状態表示
│   ├── live_view_screen.dart      # HLSライブ映像（go2rtc）
│   ├── events_screen.dart         # イベント一覧（Frigate API）
│   └── local_detection_screen.dart # on-device推論（TFLite）
├── services/
│   ├── frigate_api_service.dart   # Frigate REST APIラッパー
│   ├── mediapipe_detection_service.dart # TFLite推論エンジン
│   └── notification_service.dart # ローカル通知
└── widgets/
    ├── detection_overlay.dart     # BBoxオーバーレイ描画
    └── event_card.dart            # イベントカード
```

## セキュリティ

- **Takumi Guard**: Dartパッケージのサプライチェーン保護
- LAN内のみ接続（外部公開不可）
- VPN/ゼロトラスト経由での外部アクセスを推奨（NF-024）

## トラブルシューティング

### カメラが使えない

- iOS/Androidのカメラ権限をアプリ設定から確認してください

### モデルが見つからない

```
assets/models/efficientdet_lite0.tflite を配置してください
```

→ 上記のダウンロードコマンドを実行してください

### ライブ映像が映らない

1. go2rtcが稼働しているか確認: `http://192.168.1.100:1984`
2. ストリーム名 `balcony_sub` が go2rtc.yml に設定されているか確認
3. スマホとFrigateが同一LAN上にあるか確認
