# Security Policy

## Scope

これは個人用の dotfiles リポジトリで、公開インターネットに晒されるサービスは含まない。SECURITY.md は以下を想定している:

- ローカルマシンの dotfiles 適用によって生じる脆弱性（credential 漏洩、symlink attack、TOCTOU、privilege escalation など）
- AI agent（Claude Code）に予期せぬ権限を与える設定不備
- `pwedge` 等 playwright-cli helper 経由のブラウザ操作で AI 用 Edge プロファイルの隔離が壊れる類の blast radius 逸脱
- chezmoi templating の injection

スコープ外:
- 公開されている third-party ツール（Homebrew formula、npm packages、MCP サーバー実装など）自体の脆弱性。それぞれの upstream に報告してください
- ユーザーが fork 後に加えた改変に起因する問題

## 報告方法

GitHub の **Private vulnerability reporting** を使ってください。

1. リポジトリの "Security" タブを開く
2. "Report a vulnerability" を押す
3. 詳細（再現手順、影響範囲、対象 commit / file:line）を記載

もしくは、public Issue で「詳細は private channel で」と前置きしたうえで contact を求めてもらえれば、そこから非公開のやり取りに移します。

## 期待する応答時間

個人メンテナンスなので SLA は保証しないが、実害がある報告は 7 日以内に初動、重大なら同日〜翌日で patch を目標にする。

## 公開範囲の方針

修正後に CVE を振るかどうかは内容次第。dotfiles 特有のローカル権限問題は通常 CVE 対象外だが、公開した coordinated disclosure で crediting するかは報告者の希望に合わせる。
