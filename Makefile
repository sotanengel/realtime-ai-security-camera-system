.PHONY: lint pre-commit install-pre-commit-hook test help

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

lint: ## Run all linters locally
	./scripts/lint.sh

pre-commit: ## Run pre-commit on all files
	pre-commit run --all-files

install-pre-commit-hook: ## Install pre-commit git hook
	pre-commit install

test: ## Run Python tests
	uv run pytest tests/ -v

setup: ## Install dev dependencies and pre-commit hooks
	uv sync
	pre-commit install
	@echo "✅ セットアップ完了"
