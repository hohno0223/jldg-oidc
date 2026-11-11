# JLDG OIDC 認証補助 導入・動作確認（簡易版）

実行ホストに認証補助を配置し、検証用の一般利用者で動作を確認するまでの最短の手順である。設定の理由、詳しい確認項目と障害対応は [管理者マニュアル](ADMIN_GUIDE.md)、全体像と jldg-auth の動作仕様は [README](README.md) を参照する。利用者には [利用手順（簡易版）](USER_QUICKSTART.md) と [ユーザマニュアル](USER_GUIDE.md) を案内する。

本書の用語と前提：

- **実行ホスト**：oidc-agent と Gfarm クライアントを実行する JLDG クライアント。利用者は手元の PC から SSH でログインする。
- **OP**：JLDG の OpenID Provider（認証基盤）。`https://idp.jldg.org`。
- **RT**：リフレッシュトークン。
- 配置先は `/usr/local/jldg` とする。

## 1. 前提

- 実行ホストに Linux、Bash、stty、oidc-agent 5 系、Gfarm クライアントと XOAUTH2 を導入済みである。tcsh を使う利用者がいれば tcsh も必要である。
- Gfarm は `JWT_USER_PATH` の `!コマンド` 形式に対応した版である。
- OP に public client を登録し、authorization code flow・PKCE S256 と RT の発行を有効にしてある。
- Gfarm の TLS・issuer・audience・scope・ユーザー名の対応付けを設定し、読み取りを試す検証用ファイルを用意してある。
- 実行ホストが OP への HTTPS 接続を許可されたネットワークにあり、手元の PC に JLDG ユーザ証明書をインポートしたブラウザがある。

```bash
command -v bash stty oidc-agent oidc-keychain oidc-gen oidc-add oidc-token gfwhoami gfexport
oidc-agent --version
```

## 2. 配置する（管理者）

既存の配置ファイル・シェル起動設定・`/etc/oidc-agent/config` をバックアップしてから、配布ファイルのあるディレクトリで実行する。

```bash
sudo install -d -o root -g root -m 0755 /usr/local/jldg
sudo install -o root -g root -m 0755 jldg-auth /usr/local/jldg/
sudo install -o root -g root -m 0644 jldg-env.sh jldg-env.csh /usr/local/jldg/
sudo install -d -o root -g root -m 0755 /etc/oidc-agent/issuer.config.d
sudo install -o root -g root -m 0644 jldg-auth.conf jldg-client.json /etc/oidc-agent/
sudo install -o root -g root -m 0644 issuer.config.d/jldg /etc/oidc-agent/issuer.config.d/jldg
(
    for jldg_script in jldg-auth jldg-env.sh; do
        bash -n "/usr/local/jldg/$jldg_script" || exit
    done
    bash -n /etc/oidc-agent/jldg-auth.conf
)
```

配置したファイルは root 所有とし、一般利用者に書き込みを許さない。

## 3. 設定する（管理者）

```bash
sudoedit /etc/oidc-agent/jldg-client.json
sudoedit /etc/oidc-agent/issuer.config.d/jldg
sudoedit /etc/oidc-agent/jldg-auth.conf
sudoedit /etc/oidc-agent/config
```

| ファイル | 設定内容 |
| --- | --- |
| `jldg-client.json` | `REPLACE_WITH_REGISTERED_JLDG_CLIENT_ID` を登録済みのクライアント ID に置き換え、issuer・scope・redirect URI を OP の登録と一致させる。JSON の構文も確認する |
| `issuer.config.d/jldg` | `issuer` を `jldg-client.json` の `issuer_url` と一致させ、`pw-store` は `true` のままにする |
| `jldg-auth.conf` | 初回登録・再認証で oidc-gen に渡すオプション `JLDG_GEN_OPTIONS`（Bash の配列）を確認する。配布時の既定値は、ブラウザを自動で開かない `--no-url-call`、localhost で認証結果を受ける `--flow=code --no-scheme`、端末でパスワードを入力する `--pw-prompt=cli` 等である。クライアント JSON を別の場所に置く場合は、このファイルの `JLDG_CLIENT_CONFIG` を変更する |
| `config` | 既存の `oidc-agent`・`oidc-add` セクションに次の値を反映する。ほかの設定・セクションは残す |

```json
{
  "oidc-agent": {
    "auto-reauthenticate": false,
    "autoload": false,
    "auto-gen": false
  },
  "oidc-add": {
    "pw-prompt": "cli"
  }
}
```

これにより、agent 自身による自動読み込み・自動生成・自動再認証が無効になり、`oidc-add jldg` は端末でパスワードを求め、更新された RT を保存できるようパスワードを agent のメモリに保持する。利用者側の設定や起動オプションによる上書きがないことも確認する（[詳細版 3.3](ADMIN_GUIDE.md#33-etcoidc-agentconfig)）。

設定は agent の起動時に読み込まれる。すでに agent を起動している利用者は、停止してから起動し直す必要がある。停止は同じ利用者のほかの端末にも影響するため、影響を確認してから行う。検証用利用者では、4節の前に Bash で `eval "$(oidc-keychain --kill)"` を実行する。

NFS 等でホームを複数の実行ホストで共有する場合は、ホストごとの `OIDC_CONFIG_DIR` を設定する。設定しないと、あるホストでの RT の更新で、ほかのホストの RT が失効する（[詳細版 3.7](ADMIN_GUIDE.md#37-ホームを複数の実行ホストで共有する場合)）。

## 4. 環境と agent を準備する（検証用の一般利用者）

検証用の一般利用者の Bash で実行する。

```bash
source /usr/local/jldg/jldg-env.sh
eval "$(oidc-keychain)"
oidc-agent --status
```

**確認：** `JWT_USER_PATH` が `!jldg-auth --token` で、PATH から `jldg-auth` が見つかる。`oidc-agent --status` の表示で、バージョンが 5 系、Autoload と Auto Re-authenticate が false、Webserver が true、Confirm が false である。auto-gen は設定ファイルで確認する。

`oidc-keychain` は同じ利用者の agent が動いていれば接続し、なければ起動する。環境設定スクリプト自体は agent を操作しない。tcsh の手順は [詳細版 5.7](ADMIN_GUIDE.md#57-tcsh) を参照する。

## 5. 初回登録を確認する

アカウント `jldg` が未登録の検証用利用者で実行する。

```bash
jldg-auth
printf 'register status=%s\n' "$?"
```

認証 URL と `Browser authentication:` で始まる案内が表示されたら、この端末は待機させ、手元の PC で次の操作を行う。

1. 新しい端末を開き、案内に表示された転送オプションを付けて実行ホストへ SSH 接続する。表示されたポートが 4243 の例：

   ```bash
   ssh -N -o ExitOnForwardFailure=yes -L 4243:localhost:4243 -D 1080 YOUR_SSH_HOST_ALIAS
   ```

2. JLDG ユーザ証明書をインポートしたブラウザで SOCKS5 プロキシを `localhost:1080` に設定し、SSH を維持したまま認証 URL を開いて認証する。
3. 元の端末が `Please press Enter to try it again.` で待っている場合は、ブラウザ認証の完了後に Enter を押す。
4. 元の端末の表示に従い、暗号化パスワードを設定する。
5. 完了後、ブラウザのプロキシ設定を戻し、転送を Ctrl-C で終了する。

**確認：** `JLDG account registration completed.`、`JLDG is ready.`、`register status=0` が表示される。jldg-auth は登録後にトークンの取得まで確認してから `JLDG is ready.` を表示する。

## 6. トークンと Gfarm を確認する

```bash
oidc-add --loaded
jldg-auth --token >/dev/null
printf 'token status=%s\n' "$?"
gfwhoami
printf 'gfwhoami status=%s\n' "$?"
gfexport 'gfarm:///REPLACE_WITH_TEST_FILE' >/dev/null
printf 'gfexport status=%s\n' "$?"
```

`>/dev/null` は、トークンや取得したファイルの内容を画面に出さないために付けている。エラーは表示されるので、成否は各 status で確認する。ファイルのパスは実際の検証用パスに置き換える。

**確認：** `jldg` が読み込み済みで、`gfwhoami` が検証用利用者の Gfarm ユーザー名を表示し、各 status が0である。他方式へのフォールバックを無効にするか、ログで XOAUTH2 が使われたことを確認し、`GFARM_SASL_PASSWORD` や `sasl_password` などの別設定が使われていないことも確かめる。

## 7. 2回目以降・失効・失敗・停止を確認する

JLDG の RT は発行から1か月有効で、更新のたびに、そこから1か月有効な新しい RT に置き換わる（[詳細版 5.2](ADMIN_GUIDE.md#52-アカウントとトークン取得)）。

- **2回目以降：** 同じ端末または新しいログインで4節の接続を行い、`jldg-auth` を実行する。ブラウザ認証なしで `JLDG is ready.` が表示される。`jldg-auth --no-browser` も同じく成功する。
- **RT の失効：** OP の管理機能などで検証用の RT を失効させる。有効なアクセストークンのキャッシュが切れた後、`jldg-auth --token` が元のエラーと `JLDG reauthentication is required.` を表示して失敗し、ブラウザ認証を始めないことを確認する。続いて端末で `jldg-auth` を実行し、`The refresh token was rejected.` から再認証へ進み、`JLDG reauthentication completed.` と `JLDG is ready.` が表示されることを確認する。`jldg-auth --no-browser` では再認証せずに案内だけを表示する（[詳細版 6](ADMIN_GUIDE.md#6-再認証と失敗時の確認)）。
- **障害：** OP の停止や通信障害では、jldg-auth が再認証せずに元のエラーと案内を表示して終了することを確認する。パスワード入力中の Ctrl-C で端末設定が元に戻り、agent と環境変数が残ることも確認する。
- **停止：** Bash では `eval "$(oidc-keychain --kill)"` で agent を停止する。このコマンドは、現在のシェルの接続用変数の削除も同時に行う。停止後も `JWT_USER_PATH` は残り、`jldg-auth --token` は失敗して案内を表示する。4節の接続と `jldg-auth` で再開でき、再登録は不要である。停止の終了状態も確認する手順は [詳細版 5.5](ADMIN_GUIDE.md#55-停止と再読み込み) を参照する。

同じアカウントの初回登録・ブラウザ再認証は、複数の端末から同時に実行しない。

既存の環境を更新する場合は、[詳細版 8](ADMIN_GUIDE.md#8-更新時の確認と導入完了の判定) の更新時の注意も確認する。
