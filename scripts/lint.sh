#!/usr/bin/env bash
# lint.sh
# ローカルで全linterを実行するスクリプト
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "═══════════════════════════════════════════"
echo "  Lint チェック開始"
echo "═══════════════════════════════════════════"

# 1. Python (ruff)
echo ""
echo "▶ Python lint (ruff check)..."
uv run ruff check laptop/scripts/ tests/ && echo "  ✅ ruff check OK"

echo ""
echo "▶ Python format (ruff format --check)..."
uv run ruff format --check laptop/scripts/ tests/ && echo "  ✅ ruff format OK"

# 2. YAML (yamllint)
echo ""
echo "▶ YAML lint (yamllint)..."
if command -v yamllint &>/dev/null; then
  yamllint -c .yamllint.yml \
    raspberry-pi/docker-compose.yml \
    raspberry-pi/config/frigate.yml \
    raspberry-pi/config/go2rtc.yml \
    laptop/docker-compose.yml \
    laptop/config/frigate.yml \
    laptop/config/go2rtc.yml \
    .pre-commit-config.yaml && echo "  ✅ yamllint OK"
else
  echo "  ⚠️  yamllint がインストールされていません（スキップ）"
  echo "     pip install yamllint でインストールしてください"
fi

# 3. Markdown (markdownlint)
echo ""
echo "▶ Markdown lint (markdownlint)..."
if command -v markdownlint &>/dev/null; then
  markdownlint --config .markdownlint.json "**/*.md" && echo "  ✅ markdownlint OK"
else
  echo "  ⚠️  markdownlint がインストールされていません（スキップ）"
  echo "     npm install -g markdownlint-cli でインストールしてください"
fi

# 4. GitHub Actions SHA pinning
echo ""
echo "▶ GitHub Actions SHA pinning チェック..."
./scripts/check-github-actions-pinning.sh

# 5. ShellCheck
echo ""
echo "▶ ShellCheck..."
if command -v shellcheck &>/dev/null; then
  shellcheck scripts/*.sh && echo "  ✅ shellcheck OK"
else
  echo "  ⚠️  shellcheck がインストールされていません（スキップ）"
fi

echo ""
echo "═══════════════════════════════════════════"
echo "  ✅ 全 Lint チェック完了"
echo "═══════════════════════════════════════════"
