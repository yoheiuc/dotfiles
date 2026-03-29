.PHONY: help install install-work install-personal install-all preview preview-work preview-personal preview-all update update-work update-personal update-all doctor uninstall

help: ## このヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

install: ## 新しいMacのセットアップ (core のみ)
	bash scripts/bootstrap.sh

install-work: ## core + work アプリをインストール
	bash scripts/bootstrap.sh
	bash scripts/brew-bundle.sh sync work
	bash scripts/post-setup.sh

install-personal: ## core + personal アプリをインストール
	bash scripts/bootstrap.sh
	bash scripts/brew-bundle.sh sync personal
	bash scripts/post-setup.sh

install-all: ## core + work + personal をすべてインストール
	bash scripts/bootstrap.sh
	bash scripts/brew-bundle.sh sync all
	bash scripts/post-setup.sh

preview: ## 適用前に差分を確認 (core)
	bash scripts/preview.sh

preview-work: ## 適用前に差分を確認 (core + work)
	bash scripts/preview.sh work

preview-personal: ## 適用前に差分を確認 (core + personal)
	bash scripts/preview.sh personal

preview-all: ## 適用前に差分を確認 (core + work + personal)
	bash scripts/preview.sh all

update: ## dotfiles を最新にして適用・追加のみ (core)
	git pull origin main
	chezmoi apply
	bash scripts/brew-bundle.sh install core

update-work: ## dotfiles を最新にして適用・追加のみ (core + work)
	git pull origin main
	chezmoi apply
	bash scripts/brew-bundle.sh install work

update-personal: ## dotfiles を最新にして適用・追加のみ (core + personal)
	git pull origin main
	chezmoi apply
	bash scripts/brew-bundle.sh install personal

update-all: ## dotfiles を最新にして適用・追加のみ (core + work + personal)
	git pull origin main
	chezmoi apply
	bash scripts/brew-bundle.sh install all

doctor: ## セットアップの状態を確認
	bash scripts/doctor.sh

uninstall: ## dotfiles をアンインストール
	bash scripts/uninstall.sh
