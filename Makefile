SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
.DEFAULT_GOAL := help

.PHONY: help tips status ai-audit ai-repair ai-secrets install preview sync doctor test uninstall

PULL ?= 0

help: ## このヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

tips: ## よく使う dotfiles コマンドのヒント表示
	bash scripts/dotfiles-help.sh

status: ## 日常確認に必要な状態を短く表示
	bash scripts/status.sh

ai-audit: ## ローカル管理の AI 設定だけを詳しく確認
	bash scripts/ai-audit.sh

ai-repair: ## AI 周りのローカル drift を修復 (Serena config / MCP registration)
	bash scripts/ai-repair.sh

ai-secrets: ## Claude Code / Codex 共通の MCP credential を対話で保存
	bash scripts/ai-secrets.sh

install: ## 新しい Mac のセットアップ (Brew + chezmoi apply + post-setup)
	bash scripts/bootstrap.sh
	bash scripts/post-setup.sh

preview: ## 適用前に差分を確認
	bash scripts/preview.sh

sync: ## chezmoi apply + brew sync (cleanup 付き) + post-setup (PULL=1 で git pull も)
	@if [ "$(PULL)" = "1" ]; then git pull origin main; fi
	chezmoi apply
	bash scripts/brew-bundle.sh sync
	bash scripts/post-setup.sh

doctor: ## セットアップ状態の深い確認
	bash scripts/doctor.sh

test: ## 回帰テストを実行
	bash tests/doctor.sh
	bash tests/serena-wrapper.sh
	bash tests/ai-repair.sh
	bash tests/ai-secrets.sh
	bash tests/ai-secrets-wrapper.sh
	bash tests/dothelp.sh
	bash tests/status.sh
	bash tests/ai-audit.sh
	bash tests/playwright-zsh.sh
	bash tests/notion-cli.sh
	bash tests/ai-config.sh
	bash tests/lsp-hint.sh
	bash tests/frontend-design-skill.sh
	bash tests/find-skills.sh

uninstall: ## dotfiles をアンインストール
	bash scripts/uninstall.sh
