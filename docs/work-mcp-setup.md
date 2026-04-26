# 仕事用 MCP の setup 手順（dotfiles 管理外、必要時に install）

業務利用する SaaS の MCP は **tenant URL / access code / API token** がそれぞれの環境固有なので dotfiles baseline に乗らない。L2 採用判断は「使う時が来たら setup、判断ログにマシン install を記録」。手順だけ集約しておく（ここは on-demand に読む doc であって、毎ターン context に乗せる対象ではない）。

## 共通: Keychain wrapper の使い方

dotfiles に framework 残置済みの `~/.local/bin/mcp-with-keychain-secret`（service: `dotfiles.ai.mcp`）を介して、stdio MCP に env var を注入する。手順:

```bash
# 1. Keychain にトークン保存
security add-generic-password -U -s dotfiles.ai.mcp -a <account> -w '<secret>'

# 2. ~/.claude.json に MCP 登録（手で or claude mcp add 経由）
# wrapper が <account> を読んで env var <ENV_NAME> として stdio コマンドに渡す
{
  "mcpServers": {
    "<name>": {
      "type": "stdio",
      "command": "/Users/<you>/.local/bin/mcp-with-keychain-secret",
      "args": ["<ENV_NAME>", "dotfiles.ai.mcp", "<account>", "npx", "mcp-remote", "<remote-url>"]
    }
  }
}
```

remote HTTP MCP に header で token を渡す native pattern もあるが、Claude Code 起動時の env に `<ENV_NAME>` がないと動かない。Keychain wrapper の方が「起動環境 free」で堅牢。

## Netskope MCP（hosted preview）

- 公式 hosted: `https://mcp-preview.goskope.com/{tenant}/{access_code}/mcp`
- tools: 70+（セキュリティアラート / インシデント / DLP / CCI / Network / ポリシー）
- 必要: tenant subdomain (`<tenant>.goskope.com`) + 6-char access code + Netskope API V2 Bearer token（Application/Page/Alert/Incident/Client/Network datasearch + CCI + Incidents 権限）

setup:

```bash
# Keychain にトークン保存
security add-generic-password -U -s dotfiles.ai.mcp -a netskope-api-token -w '<TOKEN>'

# claude mcp add（半 credential な URL は手で組む）
claude mcp add --transport http --scope user netskope \
  https://mcp-preview.goskope.com/<TENANT>/<ACCESS_CODE>/mcp \
  --header "Authorization: Bearer ${NETSKOPE_API_TOKEN}"

# Claude Code 起動前に env で読み込む（zshrc に追加 or ai-secrets.env に書く）
export NETSKOPE_API_TOKEN="$(security find-generic-password -w -s dotfiles.ai.mcp -a netskope-api-token)"
```

注意: tenant URL / access code 自体も半 credential なので `~/.claude.json`（dotfiles 管理外）に置く。git に commit しない。

## Microsoft MCP for Enterprise (Entra ID 公式 read-only)

- 公式 hosted: `https://mcp.svc.cloud.microsoft/enterprise`
- tools: Entra ID admin (users / groups / devices / apps / sign-in audit / 条件付きアクセス) + 基本 device readiness（Intune の compliance 状態）
- 必要: Entra テナントで MCP Client app 登録 + admin consent + redirect URI 設定 + PowerShell module `Microsoft.Entra.Beta` で `Grant-EntraBetaMCPServerPermission`

setup（簡略）:

```powershell
# Windows / PowerShell（Entra admin 権限で実行）
Install-Module Microsoft.Entra.Beta -RequiredVersion 1.0.13
Connect-Entra
# 自分の MCP Client app を登録 → 取得した clientId を渡す
Grant-EntraBetaMCPServerPermission -ClientId <YOUR_MCP_CLIENT_APP_ID>
```

```bash
# Claude Code 側 (~/.claude.json)
{
  "mcpServers": {
    "ms-enterprise": {
      "type": "http",
      "url": "https://mcp.svc.cloud.microsoft/enterprise",
      "oauth": { "clientId": "<your-mcp-client-app-id>", "callbackPort": <port> }
    }
  }
}
```

注意: ChatGPT / Claude は **custom client ID 必須**（公式デフォルトの VS Code 用 ID は使えない）。tenant ごとに app 登録が要る。

## Jamf Pro 実 tenant 操作 (`dbankscard/jamf-mcp-server`)

- 公式の docs MCP は別物（既に baseline 化済）。これは **実 Jamf Pro tenant への操作**用
- read-only mode で運用するのが安全（`JAMF_READ_ONLY=true`）
- 必要: Jamf Pro API client (CLIENT_ID + CLIENT_SECRET)、最小権限を割り当て

setup:

```bash
# Keychain
security add-generic-password -U -s dotfiles.ai.mcp -a jamf-client-id -w '<ID>'
security add-generic-password -U -s dotfiles.ai.mcp -a jamf-client-secret -w '<SECRET>'

# Node 版を local clone（or npm 化されたら直 npx）
git clone https://github.com/dbankscard/jamf-mcp-server ~/src/jamf-mcp-server
cd ~/src/jamf-mcp-server && npm install && npm run build

# ~/.claude.json — 2 段 wrapper（CLIENT_ID と CLIENT_SECRET 両方注入）
{
  "mcpServers": {
    "jamf": {
      "type": "stdio",
      "command": "bash",
      "args": ["-lc",
        "JAMF_CLIENT_ID=$(security find-generic-password -w -s dotfiles.ai.mcp -a jamf-client-id) \
         JAMF_CLIENT_SECRET=$(security find-generic-password -w -s dotfiles.ai.mcp -a jamf-client-secret) \
         JAMF_URL=https://<tenant>.jamfcloud.com \
         JAMF_READ_ONLY=true \
         node /Users/<you>/src/jamf-mcp-server/dist/index-main.js"
      ]
    }
  }
}
```

write 解禁する場合は `JAMF_READ_ONLY=false` にする前に L2 判断ログへ書く。

## Intune 専用 MCP

- 公式版 (Microsoft MCP for Enterprise) で **基本 device readiness は covered**。専用 MCP は機能ギャップ次第
- community 候補: `pamontag-org-ghe/intune-mcp-server`（最小、Azure Container Apps self-host） / PowerShell.MCP（local PowerShell session 経由で Graph PowerShell）
- 採用判断: 公式 MCP for Enterprise を install して足りない部分を測ってから
