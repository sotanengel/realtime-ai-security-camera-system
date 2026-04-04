# GitHub Copilot 指示書

## プロジェクト概要

ベランダ向けローカルリアルタイムAI監視カメラシステム。
Wi-Fiカメラ + Frigate + go2rtc + Flutter で構成され、クラウド不依存でプライバシーを守る。

## アーキテクチャ

| ディレクトリ | 実行環境 | 技術 |
| --- | --- | --- |
| `raspberry-pi/` | Raspberry Pi | Frigate + go2rtc (CPU推論) |
| `laptop/` | ノートPC | Frigate + OpenVINO/ONNX Runtime |
| `mobile/balcony_guard_app/` | iOS/Android | Flutter + TFLite (MediaPipe) |

## コーディング規約

### Python（`laptop/scripts/`）

- Python 3.11+ を前提にする
- 型アノテーションを必ず書く（`def func(x: int) -> str:`）
- `ruff` のルールに従う（line-length: 100、select: E F W I N UP B SIM）
- `argparse` でCLIを構成する
- 関数は単一責任原則に従い小さく保つ

### Dart/Flutter（`mobile/balcony_guard_app/`）

- Riverpod で状態管理する
- go_router でナビゲーションを管理する
- サービス層（`services/`）でビジネスロジックを分離する
- ウィジェットは小さく保ち、`widgets/` に切り出す

### YAML（設定ファイル）

- コメントを英語または日本語で適切に記述する
- インデント: 2スペース
- 環境変数は `.env` で管理し、設定ファイルには直書きしない

## セキュリティ要件

- **Takumi Guard** を pip/pub のパッケージインストールに使用する
- 資格情報は `.env` ファイルで管理し、コードに直書きしない（`NF-023`）
- GitHub Actions は必ず **SHA pinning** を使用する（バージョンタグ禁止）
- 外部公開しない（LAN内 + VPN のみ）

## CI/CD

- `pre-commit run --all-files` を必ず通してからコミットする
- CI は GitHub Actions で自動実行される
- `make lint` でローカルlintを実行できる
- `make test` でテストを実行できる

## 検知対象クラス

`person` / `bird` / `cat` / `dog`

## 変更時の注意

- `raspberry-pi/config/frigate.yml` と `laptop/config/frigate.yml` は設定が重複している部分がある。両方を更新すること。
- `.env` ファイルは Git 管理外。`.env.example` を更新した場合は README も更新する。
- GitHub Actions のバージョンアップ時は必ず SHA を更新する。
