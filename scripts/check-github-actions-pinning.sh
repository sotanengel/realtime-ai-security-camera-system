#!/usr/bin/env bash
# check-github-actions-pinning.sh
# GitHub Actionsのworkflowファイルが全てSHA pinningを使用しているか検証する
# （バージョンタグ @v1, @v2 などの使用を禁止しサプライチェーン攻撃を防ぐ）
set -euo pipefail

WORKFLOWS_DIR=".github/workflows"
failed=0

if [ ! -d "$WORKFLOWS_DIR" ]; then
  echo "ℹ️  $WORKFLOWS_DIR が見つかりません（スキップ）"
  exit 0
fi

for file in "$WORKFLOWS_DIR"/*.yml "$WORKFLOWS_DIR"/*.yaml; do
  [ -f "$file" ] || continue
  while IFS= read -r line; do
    # uses: owner/repo@vX.X.X または uses: owner/repo@tag の形式を検出
    # SHA形式（40文字の16進数）は許可する
    if echo "$line" | grep -qE '^\s+uses:\s+[^#]+@v[0-9]'; then
      echo "❌ SHA pinning が必要です: $file"
      echo "   $line"
      echo "   → uses: owner/repo@<40-char-sha> # vX.X.X の形式を使用してください"
      failed=1
    fi
  done < "$file"
done

if [ "$failed" -eq 1 ]; then
  echo ""
  echo "SHA pinning 違反が検出されました。"
  echo "例: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2"
  exit 1
fi

echo "✅ 全ての GitHub Actions が SHA pinning を使用しています"
