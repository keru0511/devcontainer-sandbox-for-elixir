# devcontainer-sandbox

汎用・使い捨て Dev Container。最小ベースイメージ + 公式 Dev Container Features で構成を選べる。

## コンセプト

- **最小ベース**: `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` をベースに、必要なものだけ追加
- **Features で選択式**: 言語ランタイムやツールはコメントを外すだけで追加
- **ファイアウォール付き**: 許可ドメインリストに基づいて外部通信を制限（オプション）
- **ロックダウン**: ファイアウォール設定後は `iptables` 操作を不能化し、AIエージェントによる無効化を防止
- **使い捨て可能**: SSH マウント不要、ボリューム名に `devcontainerId` を使用して独立性を確保

## ファイル構成

```
.
├── .devcontainer/
│   ├── Dockerfile              # 最小ベースイメージ + ファイアウォール設定
│   ├── devcontainer.json       # Dev Container 設定（Features・マウント・拡張機能）
│   ├── init-firewall.sh        # ファイアウォール初期化スクリプト
│   ├── firewall-status.sh      # ファイアウォール状態確認スクリプト
│   ├── postCreate.sh           # コンテナ作成後のセットアップ
│   └── allowed-domains.conf    # 許可ドメインリスト
└── README.md
```

## 使い方

### 言語・ツールの選択

`devcontainer.json` の `features` セクションのコメントを外す。

```jsonc
"features": {
  // --- Languages ---
  "ghcr.io/devcontainers/features/node:1": { "version": "22" },  // デフォルト有効
  // "ghcr.io/devcontainers/features/python:1": { "version": "3.12" },
  // "ghcr.io/devcontainers/features/rust:1": { "profile": "minimal" },
  // "ghcr.io/devcontainers/features/go:1": { "version": "latest" },
  // "ghcr.io/devcontainers/features/java:1": { "version": "21" },
  // "ghcr.io/devcontainers/features/ruby:1": { "version": "latest" },

  // --- Tools ---
  "ghcr.io/devcontainers/features/github-cli:1": {},              // デフォルト有効
  // "ghcr.io/devcontainers/features/docker-in-docker:2": {},
  // "ghcr.io/devcontainers/features/kubectl-helm-minikube:1": {},
  // "ghcr.io/devcontainers/features/terraform:1": {}
}
```

### AI ツール

コンテナ作成後に自動インストールされる（`postCreateCommand`）:

- `claude` (`@anthropic-ai/claude-code@2.1.69`)
- `codex` (`@openai/codex@0.106.0`)
- `pnpm` (`pnpm@10.30.3`)

バージョンは `devcontainer.json` の `containerEnv` で固定しており、必要に応じて更新できる。

### ファイアウォール

起動時に `init-firewall.sh` が自動実行され、`allowed-domains.conf` に記載されたドメインと GitHub IP 範囲のみ通信を許可する。
DNS は Docker 組み込みリゾルバ（`127.0.0.11`）宛のみ許可する。

許可ドメインを追加したい場合は `allowed-domains.conf` に1行ずつ追加:

```
# allowed-domains.conf
registry.npmjs.org
api.anthropic.com
your-domain.example.com
```

ファイアウォールを無効化したい場合は `devcontainer.json` の `postStartCommand` を変更:

```jsonc
"postStartCommand": "true"
```

#### ロックダウン

ファイアウォール設定後、`iptables`/`ipset` バイナリの実行権限を root のみに制限し、passwordless sudo も削除する。これにより、コンテナ内のAIエージェントがファイアウォールを無効化することを防ぐ。

ファイアウォール状態の確認には専用スクリプトを使用:

```bash
sudo firewall-status.sh
```

#### ブロックログ

ファイアウォールにブロックされた接続はカーネルログに記録される:

```bash
dmesg | grep FW-BLOCKED
```

### SSH キー / .gitconfig

private リポジトリを使う場合、`devcontainer.json` の `mounts` セクションのコメントを外す:

```jsonc
"mounts": [
  // ...
  "source=${localEnv:HOME}/.ssh,target=/home/dev/.ssh-host,type=bind,readonly",
  "source=${localEnv:HOME}/.gitconfig,target=/home/dev/.gitconfig-host,type=bind,readonly"
]
```

コンテナ作成時に `postCreate.sh` が自動でコピーする。

### ボリューム

| ボリューム名 | マウント先 | 用途 |
|---|---|---|
| `sandbox-bashhistory-{id}` | `/commandhistory` | コマンド履歴（コンテナ固有） |
| `sandbox-claude-config-{id}` | `/home/dev/.claude` | Claude 設定（コンテナ固有） |
| `sandbox-projects` | `/home/dev/projects` | プロジェクト（コンテナ間共有） |

## セキュリティモデル

このサンドボックスが防げること:
- AIエージェントの意図しない外部通信（ホワイトリスト外のドメインへのアクセス）
- ファイアウォール設定後の `iptables` 操作（バイナリ権限制限 + sudo 削除）
- 任意 DNS サーバへの直接問い合わせ（`127.0.0.11` 以外の DNS を遮断）

このサンドボックスが防げないこと:
- ホストへのファイルシステムアクセス（マウントされたボリューム経由）
- 許可されたドメイン（GitHub, npm 等）を悪用したデータ漏洩
- より高権限の方法（ホスト側ネットワークポリシー）による制限のバイパス

本格的な隔離が必要な場合は、ホスト側の Docker ネットワークポリシーや専用の sandbox 環境を検討すること。

## 検証

```bash
# ファイアウォールが機能しているか確認
curl https://example.com          # 失敗するはず
curl https://api.github.com/zen   # 成功するはず

# ロックダウンが機能しているか確認
sudo iptables -F                  # Permission denied になるはず

# ブロックログ確認
dmesg | grep FW-BLOCKED

# AI ツールが使えるか確認
claude --version
codex --version
```
