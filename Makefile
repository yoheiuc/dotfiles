.PHONY: help tips install install-home preview preview-home update update-home sync sync-core sync-home brew-diff brew-diff-core brew-diff-home brew-add brew-add-core brew-add-home doctor test test-scripts uninstall

help: ## このヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

tips: ## よく使う dotfiles コマンドのヒント表示
	bash scripts/dotfiles-help.sh

install: ## 新しいMacのセットアップ (core のみ)
	bash scripts/bootstrap.sh core

install-home: ## core + home アプリをインストール
	bash scripts/bootstrap.sh home
	bash scripts/brew-bundle.sh sync home
	bash scripts/post-setup.sh

preview: ## 適用前に差分を確認 (現在のプロファイル)
	bash scripts/preview.sh

preview-home: ## 適用前に差分を確認 (core + home)
	bash scripts/preview.sh home

update: ## dotfiles を最新にして現在のプロファイルを適用
	PROFILE="$$(bash scripts/profile.sh get)"; \
	git pull origin main; \
	chezmoi apply; \
	bash scripts/brew-bundle.sh install "$$PROFILE"

update-home: ## dotfiles を最新にして home プロファイルを適用
	git pull origin main
	bash scripts/profile.sh set home >/dev/null
	chezmoi apply
	bash scripts/brew-bundle.sh install home

sync: ## 現在のプロファイルを cleanup 付きで同期
	PROFILE="$$(bash scripts/profile.sh get)"; \
	chezmoi apply; \
	bash scripts/brew-bundle.sh sync "$$PROFILE"

sync-core: ## core プロファイルを cleanup 付きで同期
	bash scripts/profile.sh set core >/dev/null
	chezmoi apply
	bash scripts/brew-bundle.sh sync core

sync-home: ## home プロファイルを cleanup 付きで同期
	bash scripts/profile.sh set home >/dev/null
	chezmoi apply
	bash scripts/brew-bundle.sh sync home

brew-diff: ## 現在のプロファイルとローカル Brew 実体の差分を確認
	PROFILE="$$(bash scripts/profile.sh get)"; \
	bash scripts/brew-diff.sh "$$PROFILE"

brew-diff-core: ## core プロファイルとローカル Brew 実体の差分を確認
	bash scripts/brew-diff.sh core

brew-diff-home: ## home プロファイルとローカル Brew 実体の差分を確認
	bash scripts/brew-diff.sh home

brew-add: ## 現在のプロファイルの Brewfile に追加 (KIND=brew|cask|tap NAME=...)
	PROFILE="$$(bash scripts/profile.sh get)"; \
	bash scripts/brew-add.sh "$$PROFILE" "$(KIND)" "$(NAME)"

brew-add-core: ## core Brewfile に追加 (KIND=brew|cask|tap NAME=...)
	bash scripts/brew-add.sh core "$(KIND)" "$(NAME)"

brew-add-home: ## home Brewfile に追加 (KIND=brew|cask|tap NAME=...)
	bash scripts/brew-add.sh home "$(KIND)" "$(NAME)"

doctor: ## 現在のプロファイルでセットアップ状態を確認
	bash scripts/doctor.sh

test: test-scripts ## 回帰テストを実行

test-scripts: ## shell スクリプトの回帰テストを実行
	bash tests/profile.sh
	bash tests/doctor.sh
	bash tests/brew-tools.sh
	bash tests/dothelp.sh

uninstall: ## dotfiles をアンインストール
	bash scripts/uninstall.sh
