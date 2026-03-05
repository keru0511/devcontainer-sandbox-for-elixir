# devcontainer-sandbox-for-elixir

Elixir 開発用の使い捨て Dev Container。

## コンセプト

- **Elixir 特化**: mise で Erlang/Elixir を管理、ElixirLS・LazyVim を同梱
- **最小ベース**: `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`
- **ファイアウォール付き**: 許可ドメインリストに基づいて外部通信を制限（オプション）
- **ロックダウン**: ファイアウォール設定後は `iptables` 操作を不能化し、AIエージェントによる無効化を防止
- **使い捨て可能**: SSH マウント不要、ボリューム名に `devcontainerId` を使用して独立性を確保

## ファイル構成

```
.
├── .devcontainer/
│   ├── Dockerfile              # ベースイメージ + 開発ツール + ファイアウォール設定
│   ├── devcontainer.json       # Dev Container 設定（Features・マウント・拡張機能）
│   ├── postCreate.sh           # コンテナ作成後のセットアップ（mise・Elixir・LazyVim）
│   ├── init-firewall.sh        # ファイアウォール初期化スクリプト
│   ├── firewall-status.sh      # ファイアウォール状態確認スクリプト
│   └── allowed-domains.conf    # 許可ドメインリスト
└── README.md
```

## インストール済みツール

### Dockerfile（イメージビルド時）

| ツール | 用途 |
|---|---|
| git-delta | git diff のシンタックスハイライト |
| xh | HTTP クライアント（curl の代替） |
| Neovim | エディタ |
| eza | ls の代替（ファイルツリー表示） |
| fzf | ファジーファインダー |

### postCreate.sh（コンテナ作成時）

| ツール | 用途 |
|---|---|
| mise | ランタイムバージョン管理 |
| Erlang / Elixir | 言語ランタイム（mise 経由） |
| LazyVim | Neovim 設定フレームワーク |
| claude (`@anthropic-ai/claude-code`) | AI コーディングアシスタント |
| codex (`@openai/codex`) | AI コーディングアシスタント |
| pnpm | Node.js パッケージマネージャ |

バージョンは `devcontainer.json` の `containerEnv` で固定されており、必要に応じて更新できる。

## ファイアウォール

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

### ロックダウン

ファイアウォール設定後、`iptables`/`ipset` バイナリの実行権限を root のみに制限し、passwordless sudo も削除する。これにより、コンテナ内のAIエージェントがファイアウォールを無効化することを防ぐ。

ファイアウォール状態の確認には専用スクリプトを使用:

```bash
sudo firewall-status.sh
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

## ボリューム

| ボリューム名 | マウント先 | 用途 |
|---|---|---|
| `elixir-sandbox-bashhistory-{id}` | `/commandhistory` | コマンド履歴（コンテナ固有） |
| `elixir-sandbox-claude-config-{id}` | `/home/dev/.claude` | Claude 設定（コンテナ固有） |
| `elixir-sandbox-projects` | `/home/dev/projects` | プロジェクト（コンテナ間共有） |

## セキュリティモデル

このサンドボックスが防げること:
- AIエージェントの意図しない外部通信（ホワイトリスト外のドメインへのアクセス）
- ファイアウォール設定後の `iptables` 操作（バイナリ権限制限 + sudo 削除）
- 任意 DNS サーバへの直接問い合わせ（`127.0.0.11` 以外の DNS を遮断）

このサンドボックスが防げないこと:
- ホストへのファイルシステムアクセス（マウントされたボリューム経由）
- 許可されたドメイン（GitHub, npm 等）を悪用したデータ漏洩
- より高権限の方法（ホスト側ネットワークポリシー）による制限のバイパス

## 検証

```bash
# Elixir が使えるか確認
elixir --version
mix --version

# ファイアウォールが機能しているか確認
curl https://example.com          # 失敗するはず
curl https://api.github.com/zen   # 成功するはず

# ロックダウンが機能しているか確認
sudo iptables -F                  # Permission denied になるはず

# AI ツールが使えるか確認
claude --version
```
