.PHONY: help install install-work install-home preview preview-work preview-home update update-work update-home doctor test test-scripts uninstall

help: ## このヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

install: ## 新しいMacのセットアップ (core のみ)
	bash scripts/bootstrap.sh core

install-work: ## core + work アプリをインストール
	bash scripts/bootstrap.sh work
	bash scripts/brew-bundle.sh sync work
	bash scripts/post-setup.sh

install-home: ## core + home アプリをインストール
	bash scripts/bootstrap.sh home
	bash scripts/brew-bundle.sh sync home
	bash scripts/post-setup.sh

preview: ## 適用前に差分を確認 (現在のプロファイル)
	bash scripts/preview.sh

preview-work: ## 適用前に差分を確認 (core + work)
	bash scripts/preview.sh work

preview-home: ## 適用前に差分を確認 (core + home)
	bash scripts/preview.sh home

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

update-home: ## dotfiles を最新にして home プロファイルを適用
	git pull origin main
	bash scripts/profile.sh set home >/dev/null
	chezmoi apply
	bash scripts/brew-bundle.sh install home

doctor: ## 現在のプロファイルでセットアップ状態を確認
	bash scripts/doctor.sh

test: test-scripts ## 回帰テストを実行

test-scripts: ## shell スクリプトの回帰テストを実行
	bash tests/profile.sh
	bash tests/doctor.sh

uninstall: ## dotfiles をアンインストール
	bash scripts/uninstall.sh
