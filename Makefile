.PHONY: help install install-work install-personal install-all preview preview-work preview-personal preview-all update update-work update-personal update-all doctor uninstall

help: ## このヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

install: ## 新しいMacのセットアップ (core のみ)
	bash scripts/bootstrap.sh core

install-work: ## core + work アプリをインストール
	bash scripts/bootstrap.sh work
	bash scripts/brew-bundle.sh sync work
	bash scripts/post-setup.sh

install-personal: ## core + personal アプリをインストール
	bash scripts/bootstrap.sh personal
	bash scripts/brew-bundle.sh sync personal
	bash scripts/post-setup.sh

install-all: ## core + work + personal をすべてインストール
	bash scripts/bootstrap.sh all
	bash scripts/brew-bundle.sh sync all
	bash scripts/post-setup.sh

preview: ## 適用前に差分を確認 (現在のプロファイル)
	bash scripts/preview.sh

preview-work: ## 適用前に差分を確認 (core + work)
	bash scripts/preview.sh work

preview-personal: ## 適用前に差分を確認 (core + personal)
	bash scripts/preview.sh personal

preview-all: ## 適用前に差分を確認 (core + work + personal)
	bash scripts/preview.sh all

update: ## dotfiles を最新にして現在のプロファイルを適用
	PROFILE="$$(bash scripts/profile.sh get)"; \
	git pull origin main; \
	chezmoi apply; \
	bash scripts/brew-bundle.sh install "$$PROFILE"

update-work: ## dotfiles を最新にして work プロファイルを適用
	git pull origin main
	bash scripts/profile.sh set work >/dev/null
	chezmoi apply
	bash scripts/brew-bundle.sh install work

update-personal: ## dotfiles を最新にして personal プロファイルを適用
	git pull origin main
	bash scripts/profile.sh set personal >/dev/null
	chezmoi apply
	bash scripts/brew-bundle.sh install personal

update-all: ## dotfiles を最新にして all プロファイルを適用
	git pull origin main
	bash scripts/profile.sh set all >/dev/null
	chezmoi apply
	bash scripts/brew-bundle.sh install all

doctor: ## 現在のプロファイルでセットアップ状態を確認
	bash scripts/doctor.sh

uninstall: ## dotfiles をアンインストール
	bash scripts/uninstall.sh
