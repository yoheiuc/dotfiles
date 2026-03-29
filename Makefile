.PHONY: help install install-work install-personal install-all update update-work update-personal update-all doctor uninstall

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

update: ## dotfiles を最新にして適用 (core)
	git pull origin main
	chezmoi apply
	bash scripts/brew-bundle.sh sync core

update-work: ## dotfiles を最新にして適用 (core + work)
	git pull origin main
	chezmoi apply
	bash scripts/brew-bundle.sh sync work

update-personal: ## dotfiles を最新にして適用 (core + personal)
	git pull origin main
	chezmoi apply
	bash scripts/brew-bundle.sh sync personal

update-all: ## dotfiles を最新にして適用 (core + work + personal)
	git pull origin main
	chezmoi apply
	bash scripts/brew-bundle.sh sync all

doctor: ## セットアップの状態を確認
	bash scripts/doctor.sh

uninstall: ## dotfiles をアンインストール
	bash scripts/uninstall.sh
