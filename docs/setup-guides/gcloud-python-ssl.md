# gcloud と企業プロキシ（Python 3.13 問題）

gcloud CLI は内部で Python を使う。Python 3.13 以降では `VERIFY_X509_STRICT` がデフォルトで有効になり、RFC 5280 に厳密に準拠した証明書チェーンを要求する。企業の CASB/プロキシ（Netskope, Zscaler 等）が SSL インスペクション（MITM）で使う CA 証明書は、`basicConstraints` に `critical` フラグが無い、Authority Key Identifier (AKI) が欠落している等の理由で拒否されることがある。

参考: [Netskope 環境での Python 3.13 SSL 問題](https://blog.cloudnative.co.jp/28436/)

## 症状

`brew install --cask gcloud-cli` の postflight やその後の `gcloud` コマンドで SSL エラーが発生する。

```
ssl.SSLCertVerificationError: [SSL: CERTIFICATE_VERIFY_FAILED]
  certificate verify failed: Basic Constraints of CA cert not marked critical
```

## 対策: sitecustomize.py で VERIFY_X509_STRICT を無効化

Python 3.13+ の全プロセスに対して、起動時に `VERIFY_X509_STRICT` フラグを除去するモンキーパッチを適用する。gcloud だけでなく awscli / aider / poetry 等の Python 3.13 製ツールもまとめて対応できる。

仕組み:

1. `~/.local/lib/python-ssl-compat/sitecustomize.py` が chezmoi で配置される
2. `env.zsh` がこのディレクトリを `PYTHONPATH` に追加
3. Python 3.13+ プロセスは起動時に `sitecustomize.py` を読み、SSL 検証を 3.12 相当に戻す
4. Python 3.12 以前には `hasattr` ガードで影響なし

`bootstrap.sh` は `brew bundle` の前にこのファイルをコピーするため、`gcloud-cli` cask の postflight も安全に動作する。

`make doctor` は SSL compat の有効/無効状態を表示する。

## 証明書ローテート後の無効化

Netskope 等のベンダーが RFC 5280 準拠の CA 証明書にローテートしたら、ワークアラウンドを無効化する。

```bash
# 即座に無効化（ファイルを消すだけ）
rm ~/.local/lib/python-ssl-compat/sitecustomize.py

# 新しいターミナルを開いて gcloud が動くことを確認
gcloud version

# 恒久化する場合は repo からも削除
rm ~/dotfiles/home/dot_local/lib/python-ssl-compat/sitecustomize.py
cd ~/dotfiles && git add -A && git commit -m "Remove SSL compat (Netskope cert rotated)"
chezmoi apply
```

## カスタム CA 証明書が必要な場合

プロキシ経由で `gcloud` を使う際にカスタム CA バンドルも必要な場合は、マシンローカルで設定する。

```bash
gcloud config set core/custom_ca_certs_file /path/to/corporate-ca-bundle.pem
export REQUESTS_CA_BUNDLE=/path/to/corporate-ca-bundle.pem
```

これらはマシン固有の認証情報に依存するため、dotfiles には含めず `.envrc`（direnv）等でローカル管理する。
