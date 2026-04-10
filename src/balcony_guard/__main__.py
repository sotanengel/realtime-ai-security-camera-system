"""python -m balcony_guard で実行された場合のエントリポイント。"""

import sys


def main() -> None:
    print("balcony-guard CLI ツール")
    print()
    print("利用可能なコマンド:")
    print("  balcony-guard-collect   学習データ収集 (Frigate Events API)")
    print("  balcony-guard-evaluate  ONNXモデル評価")
    print()
    print("詳細は各コマンドに --help を付けて実行してください。")


if __name__ == "__main__":
    if "--help" in sys.argv or "-h" in sys.argv:
        main()
        sys.exit(0)
    main()
