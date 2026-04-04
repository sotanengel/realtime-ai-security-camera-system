# Raspberry Pi セットアップガイド（Level 1）

最小構成でベランダ1カメラ監視PoCを動作させるためのガイドです。

## 前提条件

- Raspberry Pi 5（推奨）/ Pi 4（8GB以上）
- Docker・Docker Compose インストール済み
- Wi-Fi カメラが同一LAN内に接続されていること
- カメラが RTSP または ONVIF Profile S に対応していること

## セットアップ手順

### 1. Takumi Guard のセットアップ（サプライチェーンセキュリティ）

本プロジェクトでは [Takumi Guard](https://flatt.tech/takumi/features/guard) を使用して、
パッケージインストール時の悪意あるパッケージを自動ブロックします。

Takumi Guard の登録・設定は公式サイトを参照してください:
<https://flatt.tech/takumi/features/guard>

### 2. リポジトリの取得

```bash
git clone <このリポジトリのURL>
cd realtime-ai-security-camera-system/raspberry-pi
```

### 3. 環境変数の設定

```bash
cp .env.example .env
nano .env  # カメラのIP・ユーザ名・パスワードを設定
```

| 変数名 | 説明 |
| -------- | ------ |
| `CAMERA_IP` | カメラのIPアドレス（例: 192.168.1.100） |
| `CAMERA_USERNAME` | カメラのログインユーザ名 |
| `CAMERA_PASSWORD` | カメラのログインパスワード |
| `CAMERA_PORT` | RTSPポート（通常 554） |
| `CAMERA_MAIN_PATH` | メインストリームのパス（機種依存） |
| `CAMERA_SUB_PATH` | サブストリームのパス（機種依存） |

### 4. カメラ接続確認（任意）

```bash
# カメラのRTSPストリームが取得できるか確認
ffprobe rtsp://<ユーザ名>:<パスワード>@<カメラIP>:554/stream1
```

### 5. 設定ファイルの調整

#### ゾーン・マスクの設定

`config/frigate.yml` を開き、ベランダ映像に合わせてゾーンとマスクの座標を調整します。

- **zones**: 検知対象エリア（ベランダ内）の座標を指定
- **motion.mask**: 洗濯物・空など誤検知しやすいエリアを除外

座標はFrigate UIの「Birdseye」や設定画面から確認できます。

### 6. 起動

```bash
docker compose up -d
```

### 7. Frigate UI へアクセス

ブラウザで `http://<ラズパイのIP>:5000` を開きます。

初回アクセス時にパスワードを設定してください（NF-021: UI認証必須）。

### 8. 動作確認チェックリスト

- [ ] go2rtc（`http://<IP>:1984`）でカメラストリームが確認できる
- [ ] Frigate UIでライブ映像が表示される
- [ ] person 検知イベントが保存される
- [ ] スナップショットが `media/clips/` に保存される

## 自動復旧設定（NF-010）

`docker-compose.yml` の `restart: unless-stopped` により、
ラズパイ再起動後に自動でコンテナが起動します。

Docker が自動起動するよう設定する:

```bash
sudo systemctl enable docker
```

## Hailo AIアクセラレータ（任意）

Hailo-8 / Hailo-8L を使用する場合、Frigate の Hailo 対応設定が必要です。
詳細: <https://docs.frigate.video/configuration/object_detectors/#hailo>

## セキュリティ設定

### LAN内制限（NF-022）

ファイアウォールで外部からのアクセスを制限します:

```bash
# 外部からのFrigateポートへのアクセスをブロック
sudo ufw deny 5000
sudo ufw deny 1984
sudo ufw allow from 192.168.0.0/16 to any port 5000
sudo ufw allow from 192.168.0.0/16 to any port 1984
sudo ufw enable
```

### VPN経由外部アクセス（NF-024）

外部からアクセスする場合は WireGuard / Tailscale などの VPN を利用してください。

## トラブルシューティング

### カメラが映らない

1. `docker compose logs go2rtc` でエラーを確認
2. `.env` の `CAMERA_IP`, `CAMERA_MAIN_PATH` が正しいか確認
3. カメラのRTSPが有効か、カメラ側の設定を確認

### 推論が重い

1. `config/frigate.yml` の `detect.fps` を `3` に下げる
2. `detect.width` / `height` を `640x360` に下げる
3. Hailo AIアクセラレータの導入を検討

## ディレクトリ構成

```text
raspberry-pi/
├── docker-compose.yml    # コンテナ定義
├── config/
│   ├── frigate.yml       # Frigate 設定
│   └── go2rtc.yml        # カメラ接続設定
├── media/                # 録画・スナップショット（自動生成）
│   ├── clips/
│   └── snapshots/
├── .env                  # 資格情報（Git管理外）
├── .env.example          # 設定テンプレート
└── README.md
```
