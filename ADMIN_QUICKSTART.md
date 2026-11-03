# JLDG oidc-agent helper 導入・動作確認（簡易版）

標準の配置先 `/usr/local/share/jldg` を使う手順。動作確認は Bash で行う。設定理由やエラー時の調査は [詳細版](ADMIN_GUIDE.md) を参照する。

## 1. 事前準備

- 実行ホストに Linux、Bash、`stty`、oidc-agent **5 系**、Gfarm クライアントと XOAUTH2 を導入する。Gfarm は `JWT_USER_PATH` の `!コマンド` 形式に対応したものを使う。
- OP に public client を登録し、authorization code flow・PKCE S256 と refresh token の発行を有効にする。issuer、scope、redirect URI は配布ファイル `jldg-client.json` と一致させ、登録済み client ID を用意する。
- Gfarm の TLS・XOAUTH2・issuer・audience・ユーザー対応を設定し、読み取り確認用のディレクトリと小さなファイルを用意する。
- 実行ホストから OP へ HTTPS 接続できることを確認する。別 PC のブラウザを使う場合は、PC から実行ホストへの SSH ローカル転送と SOCKS proxy 用の動的転送を使えることを確認する。
- ブラウザを開くマシンには、JLDG の証明書がインストールされたブラウザを用意する。実行ホストと同じマシンのブラウザも使用できる。

実行ホストで確認する。見つからないコマンドがあれば先に導入する。

```bash
command -v bash stty oidc-agent-service oidc-agent oidc-gen oidc-add oidc-token grep tee cat dirname gfls gfexport
oidc-agent --version
```

**確認：すべてのコマンドが見つかり、oidc-agent は 5 系である。**

## 2. ファイルを配置する（管理者）

配布ファイルのあるディレクトリで実行する。更新の場合は、先に配置先の既存ファイルと `/etc/oidc-agent/config` をバックアップする。

```bash
sudo install -d -o root -g root -m 0755 /usr/local/share/jldg
sudo install -o root -g root -m 0755 jldg-agent.sh jldg-agent.csh jldg-agent-core.sh /usr/local/share/jldg/
sudo install -d -o root -g root -m 0755 /etc/oidc-agent/issuer.config.d
sudo install -o root -g root -m 0644 jldg-client.json /etc/oidc-agent/jldg-client.json
sudo install -o root -g root -m 0644 issuer.config.d/jldg /etc/oidc-agent/issuer.config.d/jldg
(
    for jldg_script in jldg-agent.sh jldg-agent.csh jldg-agent-core.sh; do
        bash -n "/usr/local/share/jldg/$jldg_script" || exit
    done
)
```

**確認：エラーが出ず、配置先は root 所有で一般利用者に書き込み権限がない。**

## 3. 設定する（管理者）

```bash
sudoedit /etc/oidc-agent/jldg-client.json
sudoedit /etc/oidc-agent/config
```

`jldg-client.json` の `REPLACE_WITH_REGISTERED_JLDG_CLIENT_ID` を登録済み client ID に置き換える。他の値は OP の登録内容と照合する。

`/etc/oidc-agent/config` の既存の `oidc-agent` セクションに、以下の3項目を反映する。**この例でファイル全体を置き換えず、他の設定・セクションを残す。** ファイルがない場合は [詳細版の設定手順](ADMIN_GUIDE.md#33-etcoidc-agentconfig) を確認する。

```json
{
  "oidc-agent": {
    "auto-reauthenticate": false,
    "autoload": false,
    "auto-gen": false
  }
}
```

次の点も確認する。

- `/etc/oidc-agent/issuer.config.d/jldg` の `issuer` がクライアント JSON の `issuer_url` と一致し、`pw-store` が `true` である。
- ユーザー側の設定や既存の issuer 設定・起動オプションが上記設定を上書きしていない。
- Gfarm の検証用設定に `sasl_password` がなく、検証用利用者の環境に `GFARM_SASL_PASSWORD` が設定されていない。

## 4. 初回登録する（一般利用者）

`jldg` が未登録の検証用一般利用者で実行ホストへログインし（別 PC からは SSH を使う）、Bash で実行する。**ここからは `sudo` を付けない。** 既存 agent がある場合は、設定反映のため先に `oidc-agent-service stop` を実行する。これは環境変数がないログイン直後でも service の agent を停止できる。service の管理先を変えないよう、起動時と同じ `TMPDIR` を使う。同じ利用者の他端末にも停止が影響するため、検証用利用者で行う。

```bash
unset JWT_USER_PATH
eval "$(/usr/local/share/jldg/jldg-agent.sh start)"
printf 'start status=%s\n' "$?"
```

暗号化パスワードを設定する。認証 URL が表示されたら、元の端末を待たせたまま、**JLDG の証明書がインストールされたブラウザ**で認証する。

- **実行ホストと同じマシンのブラウザを使う場合：** 認証 URL を直接開く。SSH 転送や SOCKS proxy の設定は不要である。
- **別 PC のブラウザを使う場合：** PC の別端末で、表示されたオプションを使って SSH 接続を開始する。例えばコールバック用ポートが `4243` の場合：

```bash
ssh -N -o ExitOnForwardFailure=yes -L 4243:localhost:4243 -D 1080 YOUR_SSH_HOST_ALIAS
```

別 PC の場合、接続先を実行ホストの実際の SSH 接続先に置き換え、`-L` のポートは表示に合わせる。普段必要な踏み台・鍵等のオプションも使う。ブラウザの SOCKS5 proxy を `localhost:1080` に設定する。SSH 接続を維持したまま認証 URL を開く。元の端末の処理が完了したら、ブラウザの proxy 設定を元に戻し、転送端末を Ctrl-C で終了する。

`Please press Enter to try it again.` が出ても、SSH やブラウザの準備中は Enter を押さず待たせる。ブラウザ認証を完了してから元の端末で Enter を押す。生成開始・受付の3行は helper が非表示にする。登録完了は次の成功表示と終了状態で確認する。

**確認：元の端末に `JLDG authentication is ready for Gfarm.` と `start status=0` が表示される。**

## 5. 接続を確認する（同じ一般利用者・同じ Bash）

```bash
printenv JWT_USER_PATH
/usr/local/share/jldg/jldg-agent.sh status
oidc-token --force-new jldg >/dev/null
printf 'token status=%s\n' "$?"
```

**確認：** `JWT_USER_PATH` は `!oidc-token --time=60 jldg`、`status` は `Agent: reachable` と `JLDG account: loaded` を表示する。agent の `Autoload` と `Auto Re-authenticate` は `false`、`Webserver` は `true`、`token status=0` である。`status` 自体はトークンを取得・更新しない。

下記の2つのパスを実際の検証用パスに置き換えて実行する。

```bash
gfls 'gfarm:///REPLACE_WITH_TEST_DIRECTORY'
printf 'gfls status=%s\n' "$?"
gfexport 'gfarm:///REPLACE_WITH_TEST_FILE' >/dev/null
printf 'gfexport status=%s\n' "$?"
```

**確認：両方の status が 0 である。** 検証用設定で他の認証方式への切り替えを無効にするか、サーバーログ等で **XOAUTH2 を使ったことも確認する**。

## 6. 停止・再読み込みを確認する（同じ Bash）

```bash
eval "$(/usr/local/share/jldg/jldg-agent.sh stop)"
printf 'stop status=%s\n' "$?"
printenv JWT_USER_PATH OIDC_SOCK OIDCD_PID OIDCD_PID_FILE
```

**確認：`stop status=0` で、`printenv` は何も表示しない。**

```bash
unset JWT_USER_PATH
eval "$(/usr/local/share/jldg/jldg-agent.sh start)"
printf 'reload status=%s\n' "$?"
```

暗号化パスワードを入力する。**確認：正常な保存済みアカウントではブラウザ認証なしで `reload status=0` となる。** 続けて手順5を再実行し、トークン取得と Gfarm 接続が成功すれば基本確認は完了。

tcsh 利用者へ配布する場合は、追加で [README の tcsh 手順](README.md#開始と停止) による開始・停止と、tcsh からのトークン取得・Gfarm 接続を確認する。失効時の再認証などの追加確認や、途中で失敗した場合の調査は [詳細版](ADMIN_GUIDE.md) を参照する。
