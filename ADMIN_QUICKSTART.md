# JLDG OIDC 認証補助 導入・動作確認（簡易版）

配置先を `/usr/local/jldg` とする。設定理由や障害対応は [詳細版](ADMIN_GUIDE.md) を参照する。

## 1. 前提

- Linux、Bash、stty、oidc-agent 5 系、Gfarm と XOAUTH2 を導入する。tcsh を使う利用者には tcsh も必要である。
- Gfarm は `JWT_USER_PATH` の `!コマンド` 形式に対応した版を使う。
- OP に public client を登録し、authorization code flow・PKCE S256 と refresh token 発行を有効にする。
- Gfarm の TLS・issuer・audience・scope・ユーザー対応を設定し、読み取り用の検証ファイルを用意する。
- 実行ホストから OP へ HTTPS 接続でき、JLDG の証明書がインストールされたブラウザを使えることを確認する。

```bash
command -v bash stty oidc-agent oidc-keychain oidc-gen oidc-add oidc-token gfls gfexport
oidc-agent --version
```

## 2. 配置する（管理者）

既存の配置ファイル・シェル起動設定・`/etc/oidc-agent/config` をバックアップしてから実行する。

```bash
sudo install -d -o root -g root -m 0755 /usr/local/jldg
sudo install -o root -g root -m 0755 jldg-auth jldg-token /usr/local/jldg/
sudo install -o root -g root -m 0644 jldg-env.sh jldg-env.csh /usr/local/jldg/
sudo install -d -o root -g root -m 0755 /etc/oidc-agent/issuer.config.d
sudo install -o root -g root -m 0644 jldg-auth.conf jldg-client.json /etc/oidc-agent/
sudo install -o root -g root -m 0644 issuer.config.d/jldg /etc/oidc-agent/issuer.config.d/jldg
(
    for jldg_script in jldg-auth jldg-token jldg-env.sh; do
        bash -n "/usr/local/jldg/$jldg_script" || exit
    done
    bash -n /etc/oidc-agent/jldg-auth.conf
)
```

ファイルは root 所有で一般利用者に書き込みを許さない。

## 3. 設定する（管理者）

```bash
sudoedit /etc/oidc-agent/jldg-client.json
sudoedit /etc/oidc-agent/jldg-auth.conf
sudoedit /etc/oidc-agent/config
```

クライアント JSON の client ID を登録済みの値に置き換え、issuer・scope・redirect URI を OP と一致させる。JSON は正しいことを前提とし、helper は構文検査しない。

`jldg-auth.conf` は信頼する管理者用の Bash 設定で、`JLDG_GEN_OPTIONS` 配列が初回登録・再認証の共通オプションを指定する。GUI 自動起動を避けるための `--no-url-call`、localhost コールバック用の `--no-scheme --flow=code`、CLI パスワード入力等の既定値を確認する。JSON のパスは `JLDG_CLIENT_CONFIG` で指定する。

`/etc/oidc-agent/config` の既存の `oidc-agent`・`oidc-add` セクションに次を反映する。他の設定・セクションは残す。

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

利用者側設定・起動オプションによる上書きがないことも確認する。issuer 設定は `issuer` を一致させ、`pw-store` を `true` にする。これにより `oidc-add jldg` の CLI 入力とパスワードのメモリ保持が既定となり、`--pw-prompt=cli`・`--pw-store` を省略できる。設定変更後は、同じ利用者の他端末への影響を確認したうえで、その利用者の Bash で `eval "$(oidc-keychain --kill)"` を実行して既存 agent を停止する。

## 4. 環境と agent を準備する（一般利用者）

ここからは sudo を付けず、検証用一般利用者の Bash で実行する。

```bash
source /usr/local/jldg/jldg-env.sh
eval "$(oidc-keychain)"
oidc-agent --status
```

**確認：** `JWT_USER_PATH` は `!jldg-token`、PATH から `jldg-auth` と `jldg-token` が見つかる。agent のバージョンは5系で、Autoload・Auto Re-authenticate は false、Webserver は true、Confirm は false である。auto-gen は設定ファイルでも確認する。

`oidc-keychain` は起動済み agent に再接続し、なければ起動する。環境設定スクリプト自体は agent を操作しない。tcsh の手順は [詳細版](ADMIN_GUIDE.md#57-tcsh) を参照する。

## 5. 初回登録・保存済みアカウントの読み込み

未登録の検証用利用者なら次を実行する。

```bash
jldg-auth
printf 'register status=%s\n' "$?"
```

`jldg-auth` は保存済みの jldg がなければ初回登録、あれば再認証を行う。単に未読み込みの場合は、この節の末尾の oidc-add を使う。

暗号化パスワードを設定し、**JLDG の証明書がインストールされたブラウザ**で認証する。

- 同じマシンのブラウザなら認証 URL を直接開く。
- 別 PC なら、その PC の別端末で表示されたポートを使って転送を準備する。例：

```bash
ssh -N -o ExitOnForwardFailure=yes -L 4243:localhost:4243 -D 1080 YOUR_SSH_HOST_ALIAS
```

ブラウザの SOCKS5 proxy を localhost:1080 に設定して認証 URL を開く。Enter 待ちになっても認証完了まで押さない。元の端末で処理が完了したら proxy を元に戻し、転送を Ctrl-C で終了する。

**確認：** `JLDG account registration completed.` と `register status=0` が表示される。これは oidc-gen の完了であり、トークン確認は次節で行う。

保存済みアカウントを新しい agent に読み込む場合は、登録を繰り返さず次を使う。

```bash
oidc-add jldg
```

`--accounts` は keychain に付けない。5.3.6 では `oidc-prompt` が見つかると内部の oidc-add が GUI 入力になるため、接続と読み込みを分ける。

## 6. トークンと Gfarm を確認する

```bash
oidc-add --loaded
jldg-token >/dev/null
printf 'token status=%s\n' "$?"
gfls 'gfarm:///REPLACE_WITH_TEST_DIRECTORY'
printf 'gfls status=%s\n' "$?"
gfexport 'gfarm:///REPLACE_WITH_TEST_FILE' >/dev/null
printf 'gfexport status=%s\n' "$?"
```

**確認：** jldg が読み込み済みで各 status が0となる。パスは実際の検証用パスへ置き換える。他方式へのフォールバックを無効にするかログで XOAUTH2 の使用を確認し、`GFARM_SASL_PASSWORD` や `sasl_password` 等の別設定が使われていないことも確かめる。

`>/dev/null` は、トークンや取得ファイルの内容を画面に出さないために付けている。エラーは表示し、成否は各 status で確認する。

## 7. 再ログイン・失効・失敗・停止を確認する

- 再ログイン後は4節と同じ手順で環境設定を読み込み、`oidc-keychain` で再接続し、`oidc-add jldg` で読み込む。自動実行は任意であり、Bash・tcsh の設定例は [README](README.md#再ログイン時の自動接続読み込み任意) と [詳細版](ADMIN_GUIDE.md#57-tcsh) を参照する。
- 検証用 refresh token の失効後、更新が必要になった状態で jldg-token が失敗し、標準エラーに復旧案内だけを追加することを確認する。有効なキャッシュが残っている場合、取得は成功し得る。
- 再認証が必要なら `jldg-auth` を利用者が明示実行し、トークン・Gfarm を再確認する。ラッパーは再認証を開始しない。
- 通信障害ではネットワークを復旧して再試行する。パスワード入力中の Ctrl-C では端末設定が戻り、agent や環境設定は残ることを確認する。
- Bash での停止は `eval "$(oidc-keychain --kill)"` で行い、出力された接続用変数の削除コマンドも実行する。停止後も `JWT_USER_PATH` は残り、トークン取得は失敗して復旧案内を表示する。停止はトークンの取り消しではない。再開は4節の接続手順と `oidc-add jldg` を使い、再登録は行わない。詳細版の [停止の終了状態も確認する手順](ADMIN_GUIDE.md#55-停止と再読み込み) と [tcsh の手順](ADMIN_GUIDE.md#57-tcsh) も参照する。
