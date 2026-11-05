# JLDG OIDC 認証補助 管理者マニュアル

本書は、実行ホストへのインストールと、利用者としての動作確認を行う手順を示す。実装や設定の補足は [README.md](README.md) を参照する。

以下の例ではスクリプトを `/usr/local/jldg` に配置する。配置先を変更する場合は、本書と利用者向けの操作例を合わせて変更する。

## 1. 作業の分担と前提

| 作業 | 実行する場所・権限 |
|---|---|
| パッケージ導入、ファイル配置、システム設定 | oidc-agent と Gfarm クライアントを実行する Linux ホスト。管理者権限を使用 |
| OIDC クライアント登録、scope・audience の調整 | JLDG の OpenID Provider（OP）の管理画面等 |
| Gfarm の TLS・XOAUTH2・ユーザー名の対応付けの設定 | 対象 Gfarm の管理者がサーバー・クライアント双方で実施 |
| 標準ツールによる agent 操作、初回登録・再認証、Gfarm 接続確認 | Linux ホストへログインした検証用の一般利用者。`sudo` を付けない |
| ブラウザ操作 | 手元の PC。JLDG の証明書が設定されたブラウザを使う |
| SSH ローカル転送・SOCKS5 プロキシ | 手元の PC で設定 |

アカウント設定と agent は利用者ごとに管理する。各利用者が自分の OP アカウントで登録する。検証では専用の一般利用者と、その利用者の OP アカウントを用意する。

必要なものは以下のとおりである。

- Linux、Bash、oidc-agent 5 系。tcsh 利用者にも案内する場合は tcsh。
- `oidc-keychain`、`oidc-agent`、`oidc-gen`、`oidc-add`、`oidc-token` と、パッケージの依存関係。
- `stty` 等の標準コマンド。
- `JWT_USER_PATH` の `!コマンド` 形式に対応した Gfarm クライアントと XOAUTH2 メカニズム。
- 実行ホストから OP への HTTPS 接続と、JLDG の証明書が設定されたブラウザ。
- 手元の PC から実行ホストへの SSH ローカルポート転送と動的転送（SOCKS5 プロキシ）。手元の PC のブラウザから OP へは、このプロキシを通して接続する。
- 時計が同期している実行ホスト・Gfarm サーバーと、必要な CA 証明書。

## 2. パッケージと OP の準備

### 2.1 oidc-agent と Gfarm クライアント

oidc-agent は、使用する OS に対応したパッケージと依存関係を導入する。ディストリビューションの標準パッケージが 4 系の場合は、本手順の前提を満たさない。導入元の選択は [oidc-agent 公式 Linux インストール手順](https://indigo-dc.github.io/oidc-agent/installation/install/) を参照する。

実行ホストで以下を確認する。最終的には検証用利用者のログイン環境でも同じコマンドが見つかる必要がある。

```bash
command -v bash stty oidc-keychain oidc-agent oidc-gen oidc-add oidc-token
oidc-agent --version
oidc-gen --version
oidc-add --version
oidc-token --version
command -v gfwhoami gfexport
```

期待結果：コマンドがすべて見つかり、oidc-agent 関連コマンドが 5 系で揃っている。tcsh の確認を行う場合は `tcsh --version` も確認する。Gfarm の導入済み版が `!コマンド` 形式に対応するかは、その版の仕様で確認する。

### 2.2 OIDC クライアント

OP に、次の条件を満たすクライアントを登録する。実際のクライアント ID、許可する scope と audience は OP・Gfarm の管理者間で決定する。

| 項目 | 配布ファイルの設定・必要条件 |
|---|---|
| issuer | `https://idp.jldg.org` |
| クライアント種別 | public client。client secret を配布しない |
| フロー | authorization code flow と PKCE S256 |
| scope | `openid offline_access jldg`。リフレッシュトークンが発行されること |
| redirect URI | 以下の5つを OP とクライアント JSON の両方へ登録 |

```text
http://localhost:4242
http://localhost:4243
http://localhost:4244
http://localhost:4245
http://localhost:4246
```

末尾の `/` の有無も含めて一致させる。oidc-agent が利用できる候補を選ぶため、実行ホスト側で少なくとも1つのポートが使用可能である必要がある。手元の PC でも、選択された同じポートと SOCKS5 プロキシ用の1080番ポートを SSH 転送に使える必要がある。

Gfarm が検証する audience がトークンに入るよう OP を設定する。scope 名と audience、クライアント ID が同じ値になるとは限らない。`jldg-token` はトークン取得時に `--aud` を指定しない。

## 3. ファイル配置と設定

更新前に、配置済みスクリプト・設定ファイル・利用者のシェル起動設定をバックアップする。既存 agent を停止する場合は、その利用者の他端末・他アカウントへの影響を確認する。

### 3.1 認証補助スクリプトと設定ファイルの配置

配布ファイルのあるディレクトリで実行する。

```bash
sudo install -d -o root -g root -m 0755 /usr/local/jldg
sudo install -o root -g root -m 0755 jldg-auth jldg-token /usr/local/jldg/
sudo install -o root -g root -m 0644 jldg-env.sh jldg-env.csh /usr/local/jldg/
sudo install -d -o root -g root -m 0755 /etc/oidc-agent/issuer.config.d
sudo install -o root -g root -m 0644 jldg-auth.conf jldg-client.json /etc/oidc-agent/
sudo install -o root -g root -m 0644 issuer.config.d/jldg /etc/oidc-agent/issuer.config.d/jldg
```

配置先ファイルと親ディレクトリを一般利用者が書き換えられないことを確認する。クライアント JSON は public client 情報であり、利用者のトークンやパスワードを書かない。

### 3.2 クライアント JSON と issuer 設定

```bash
sudoedit /etc/oidc-agent/jldg-client.json
sudoedit /etc/oidc-agent/issuer.config.d/jldg
```

`jldg-client.json` の `REPLACE_WITH_REGISTERED_JLDG_CLIENT_ID` を登録済みのクライアント ID に変更する。issuer、scope、redirect URI は前節で決定した内容に合わせる。

issuer 設定は次の内容を基本とする。`issuer` はクライアント JSON の `issuer_url` と一致させる。

```json
{
  "issuer": "https://idp.jldg.org",
  "pw-store": true
}
```

`pw-store` は、更新されたリフレッシュトークンを暗号化アカウントファイルへ保存するために、暗号化パスワードを agent のメモリに保持する設定である。この issuer 設定が有効なら、`oidc-add jldg` に `--pw-store` を付ける必要はない。[issuer 設定の公式説明](https://indigo-dc.github.io/oidc-agent/configuration/issuers/)

同じ issuer の設定が `/etc/oidc-agent/issuer.config` や利用者側にも存在する場合は、そこで `pw-store` が上書きされていないか確認する。`issuer.config.d/jldg` を配置しただけで他の設定より優先されるとは限らない。

標準のクライアント JSON の配置先を変える場合のみ、利用者の環境変数 `JLDG_CLIENT_CONFIG` にそのパスを指定する。既存アカウントのクライアント ID や redirect URI は、この JSON を変更しただけでは更新されない。既存アカウントの変更は OP の設定と合わせて別途計画する。

### 3.3 `/etc/oidc-agent/config`

パッケージが配置した既存の設定ファイルを編集する。

```bash
sudoedit /etc/oidc-agent/config
```

以下は既存設定へ反映する差分であり、ファイル全体を置き換えるものではない。`oidc-agent`・`oidc-add` の該当項目を編集し、他の項目・セクションも残す。設定ファイルが存在しない場合は、5 系の導入状態と配布パッケージの既定設定を確認してから作業する。

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

| 設定 | 運用上の意味 |
|---|---|
| `auto-reauthenticate: false` | agent は自動で再認証を始めず、`jldg-auth` を利用者が端末で実行する |
| `autoload: false` | トークン要求時の自動読み込みを無効にし、未読み込み時は利用者が oidc-add で読み込む |
| `auto-gen: false` | トークン要求をきっかけとする設定の自動作成を無効にする。`jldg-auth` による明示的な初回登録は可能 |
| `oidc-add.pw-prompt: "cli"` | 手動のアカウント読み込みで暗号化パスワードを端末から入力する |

その他は次の既定値を基本とする。

| セクション・項目 | 値 | 確認する理由 |
|---|---|---|
| `oidc-agent.webserver` | `true` | localhost コールバックを受ける |
| `oidc-agent.confirm` | `false` | トークン要求ごとに確認操作を求めない |
| `oidc-agent.lifetime` | `0` | アカウントを時間経過で自動アンロードしない。トークン自体の寿命とは別 |
| `oidc-agent.group` | `null` | 同じ利用者のプロセスから使う |
| `oidc-agent.debug_logging` | `false` | 通常運用ではデバッグログを無効にする |
| `oidc-gen.default_gpg_key` | `null` | 本手順では GPG 鍵の代わりに暗号化パスワードを使う |

通常の読み込みは上記の CLI 既定値と issuer の `pw-store: true` により `oidc-add jldg` だけで行える。設定項目の基準は [公式 5.3.6 の既定設定](https://github.com/indigo-dc/oidc-agent/blob/v5.3.6/config/config) を参照する。

利用者の oidc-agent ディレクトリ内の `config` はシステム設定を上書きできる。利用者が `OIDC_USER_CONFIG` で別ファイルを指定している場合も確認する。また、システム側・利用者側の `oidc-agent-service.options` に既存の起動オプションがないか確認する。これらの設定は JLDG 以外のアカウントにも影響する。[設定の優先順位](https://indigo-dc.github.io/oidc-agent/configuration/config/)・[service の設定](https://indigo-dc.github.io/oidc-agent/usage/oidc-agent-service/)

設定変更後は、利用者として5.5または5.7の停止手順を実行してから、5節の起動・再接続手順を実行して反映する。起動時と同じ `TMPDIR` を使い、他端末への影響を確認する。

### 3.3.1 管理者指定の oidc-gen オプション

`/etc/oidc-agent/jldg-auth.conf` は、初回登録・再認証に使うオプションを設定するファイルである。オプションは `JLDG_GEN_OPTIONS` に記載し、管理者のみ編集できる権限にする。

```bash
JLDG_CLIENT_CONFIG=${JLDG_CLIENT_CONFIG:-/etc/oidc-agent/jldg-client.json}
JLDG_GEN_OPTIONS=(
    --pub --prompt=none --pw-prompt=cli --confirm-default
    --flow=code --no-scheme --no-url-call
)
```

`jldg-auth` は保存済みアカウント `jldg` がなければ初回登録、あれば再認証を行う。登録済みならトークンが有効でも再認証へ進むため、単に未読み込みの場合は `oidc-add jldg` を使う。

標準以外の設定ファイルを使う場合は利用者の `JLDG_AUTH_CONFIG` で指定する。アカウント名は `jldg` とする。

環境設定の `JLDG_HELPER_DIR` は配置先を変更した場合だけ指定する。既定は `/usr/local/jldg`。環境設定スクリプトは PATH に配置先を加え、JWT_USER_PATH を !jldg-token に設定する。agent への接続は5節の手順で行う。

### 3.4 Gfarm の準備

Gfarm 管理者は TLS、XOAUTH2、信頼する issuer、要求する audience・scope、JWT のユーザー識別 claim と Gfarm ユーザーとの対応を設定する。クライアントの SASL メカニズムは検証時に `XOAUTH2` に限定する。必要な `sasl_user`、または claim からのユーザー名取得も設定する。[Gfarm 公式 SASL 認証手順](https://oss-tsukuba.org/share/doc/gfarm/html/ja/user/auth-sasl.html)

利用者の Gfarm 設定は `GFARM_CONFIG_FILE` の指定先、未指定時は `~/.gfarm2rc` を確認し、システム設定も合わせて確認する。`GFARM_SASL_PASSWORD` や `sasl_password` が残っていると `JWT_USER_PATH` より優先される。検証用設定から除去し、トークン取得に `jldg-token` が使われるようにする。既存の秘密情報の値を端末や記録へ出力しない。[Gfarm 設定の公式説明](https://oss-tsukuba.org/share/doc/gfarm/html/ja/ref/man5/gfarm2.conf.5.html)

## 4. インストール後の静的確認

実行ホスト上で、agent を起動せずに確認する。

```bash
ls -ld /usr/local/jldg /etc/oidc-agent /etc/oidc-agent/issuer.config.d
ls -l /usr/local/jldg/jldg-auth /usr/local/jldg/jldg-token
ls -l /usr/local/jldg/jldg-env.sh /usr/local/jldg/jldg-env.csh
ls -l /etc/oidc-agent/jldg-auth.conf /etc/oidc-agent/jldg-client.json
(
    for jldg_script in jldg-auth jldg-token jldg-env.sh; do
        bash -n "/usr/local/jldg/$jldg_script" || exit
    done
    bash -n /etc/oidc-agent/jldg-auth.conf
)
```

配置ファイルは root 所有で、実行する2コマンドは実行可能、source する環境設定と管理者設定は一般利用者が読めることを確認する。スクリプトの構文検査はファイルごとに行う。tcsh 用は5.7の実際の source 操作で確認する。

クライアント JSON の構文と必須項目、クライアント ID が置換済みであること、issuer・scope・redirect URI が OP と一致することを確認する。issuer 設定の pw-store が true、oidc-add の pw-prompt が cli であることと、利用者側設定・service オプションによる上書きも確認する。

## 5. 利用者としての動作確認

専用の一般利用者でログインする。5.7以外は Bash を使い、ここからは sudo を付けない。実トークンを表示するコマンドには >/dev/null を付ける。

### 5.1 環境設定・agent 準備・初回登録

```bash
source /usr/local/jldg/jldg-env.sh
command -v jldg-auth jldg-token
printenv JWT_USER_PATH
eval "$(oidc-keychain)"
oidc-agent --status
oidc-gen --accounts
```

期待結果：両コマンドが配置先から見つかり、JWT_USER_PATH が !jldg-token となり、oidc-agent --status で接続を確認できる。同じ利用者・同じホストの agent があれば再利用し、なければ起動する。初回起動も再接続もこの手順を使う。

agent の稼働版が 5 系、Autoload・Auto Re-authenticate が false、Webserver が true、Confirm が false であることを確認する。auto-gen は設定ファイルでも確認する。項目の表記は導入版に従う。

`jldg` が未登録の検証用利用者で初回登録を確認する。

```bash
jldg-auth
printf 'register status=%s\n' "$?"
```

初回は手元の PC の **JLDG の証明書が設定されたブラウザ**で認証する。元の端末は認証待ちのままにする。

手元の PC で新しい端末を開き、実行ホストへの SSH 転送を準備する。コールバック用ポート4243の例：

```bash
ssh -N -o ExitOnForwardFailure=yes -L 4243:localhost:4243 -D 1080 YOUR_SSH_HOST_ALIAS
```

接続先を実際の実行ホストに置き換え、鍵・踏み台等の普段の指定を使う。-L のポートは URL と案内に合わせる。手元の PC のブラウザの SOCKS5 プロキシを localhost:1080 に設定し、SSH を維持したまま認証 URL を開く。OP への接続には -D、localhost コールバックには -L を使う。両ポートが PC 側で利用可能であることを確認する。

Please press Enter to try it again. と表示された場合は、ブラウザ認証が完了するまで押さず、完了後に元の端末で Enter を押す。OP の認証セッションが失効した場合は jldg-auth を再実行する。

ブラウザ認証後、元の端末の表示に従って保存用の暗号化パスワードを設定・確認する。処理が終わったら、プロキシを元に戻し転送を Ctrl-C で終了する。

期待結果：認証 URL・パスワード入力案内が表示され、選択ポートが転送案内と一致する。初回登録の完了表示 `JLDG account registration completed.` と register status=0 を確認する。

### 5.2 アカウント・トークン取得

```bash
oidc-add --loaded
jldg-token >/dev/null
printf 'token status=%s\n' "$?"
```

期待結果：jldg が読み込み済みで token status=0。取得に失敗した場合は非0となり、元のエラーと復旧案内が標準エラーに表示される。

--time=60 は残存有効時間の要求であり、トークンの寿命を60秒にする指定ではない。有効キャッシュがあれば返し、必要なら agent が通常の更新を行う。[oidc-token の仕様](https://indigo-dc.github.io/oidc-agent/usage/oidc-token/options/)

JLDG のリフレッシュトークンは発行から1か月有効である。アクセストークンの更新に成功すると、新しいリフレッシュトークンが発行され、その時点から再び1か月有効になる。保存済みのアクセストークンを使うだけでは期限は延びない。更新が行われないまま1か月が経過すると期限が切れ、ブラウザでの再認証が必要になる。アクセストークンの更新は期限切れ前にも行われるため、期限の起点は実際に新しいリフレッシュトークンが発行された時点となる。

有効期間と更新時の再発行は OP 側の設定・実装による。導入先の OP で、有効期間が1か月であり、更新時の再発行と期限の起算方法がこの運用と一致することを確認する。認証補助スクリプトが有効期間を設定するわけではない。

個々のリフレッシュトークンの有効期限日時は、通常の利用手順では表示されない。`oidc-token --expires-at` が表示するのはアクセストークンの期限である。更新できるかを確認する場合は、5.4の手順を使う。

暗号化ファイルの保存先は通常 ~/.config/oidc-agent または ~/.oidc-agent、OIDC_CONFIG_DIR を指定した場合はそのディレクトリである。利用者本人の所有とし、ディレクトリ0700・アカウントファイル0600を基本にする。内容を表示する必要はない。[公式説明](https://indigo-dc.github.io/oidc-agent/configuration/directory/)

### 5.3 Gfarm 接続

```bash
JLDG_TEST_FILE='gfarm:///REPLACE_WITH_TEST_FILE'
gfwhoami
printf 'gfwhoami status=%s\n' "$?"
gfexport "$JLDG_TEST_FILE" >/dev/null
printf 'gfexport status=%s\n' "$?"
```

ファイルのパスは実際の検証用パスに置き換える。`gfwhoami` により検証用利用者の Gfarm ユーザー名が表示され、ファイル取得が成功し、両 status が0となることを確認する。他方式へのフォールバックを無効にするか、ログで XOAUTH2 を使用したことも確認する。成功だけでは sharedsecret・GSI 等の別方式や、sasl_password 等の別トークン設定を除外できない。

### 5.4 保存済みアカウントの読み込みと更新確認

新しい agent には利用者が標準コマンドで読み込む。

```bash
oidc-add jldg
jldg-token >/dev/null
printf 'loaded token status=%s\n' "$?"
oidc-token --force-new jldg >/dev/null
printf 'refresh status=%s\n' "$?"
```

必要なら暗号化パスワードを入力し、正常なアカウントではブラウザ認証なしで成功する。`jldg-token` は有効なキャッシュを返す場合があるため、その成功だけではリフレッシュトークンを現在利用できるかは分からない。

`--force-new` はキャッシュを使わず、認証基盤へ新しいアクセストークンを要求する。この手順では、読み込み済みのリフレッシュトークンで実際に更新を試みる。refresh status=0 ならその時点で更新できることを確認できるが、将来の有効期限日時を確認する操作ではない。更新されたリフレッシュトークンが保存されることも、次節の停止・再読み込み後にトークン取得が成功することで確認する。

通信障害、agent への未接続やアカウントの未読み込みでも失敗するため、更新に失敗しただけではリフレッシュトークンの期限切れとは断定しない。認証基盤からリフレッシュトークンが無効との応答がある場合は、6.1の手順で再認証する。

CLI 入力とパスワード保持は3節の管理者設定による。`--pw-prompt=cli`・`--pw-store` を省略しても、必要な入力が端末に表示されることを確認する。本手順では oidc-keychain に `--accounts jldg` を付けない。5.3.6 は `oidc-prompt` が見つかると内部の oidc-add に `--pw-prompt=gui` を付け、CLI 既定値を上書きするためである。これはその内部呼び出しだけに適用され、以降の手動の oidc-add の既定値は変えない。[5.3.6 の実装](https://github.com/indigo-dc/oidc-agent/blob/v5.3.6/src/oidc-keychain/oidc-keychain)

### 5.5 停止と再読み込み

同じ利用者の共有 agent を使う他端末・他アカウントへの影響を確認してから停止する。Bash の通常の停止操作は `eval "$(oidc-keychain --kill)"` であり、agent を停止し、出力された削除コマンドで現在のシェルの接続用変数も解除する。

検証では、停止処理自体の終了状態も確認するため、出力を変数に受け取り、成功時だけ評価する。単に eval の終了状態を見ると、停止処理の失敗を見落とす場合がある。

```bash
jldg_stop_commands=$(oidc-keychain --kill)
jldg_stop_status=$?
if (( jldg_stop_status == 0 )); then
    eval "$jldg_stop_commands"
    jldg_stop_status=$?
fi
printf 'stop status=%s\n' "$jldg_stop_status"
unset jldg_stop_commands jldg_stop_status
jldg-token >/dev/null
printf 'stopped token status=%s\n' "$?"
printenv JWT_USER_PATH
```

期待結果：stop status=0 で、現在のシェルの OIDC_SOCK・OIDCD_PID・OIDCD_PID_FILE が解除され、取得は非0となり、標準エラーに復旧案内が表示され、JWT_USER_PATH は !jldg-token のままである。他端末の接続用変数は変更されない。stop status が非0なら停止処理のエラーを確認する。停止は発行済みトークンの取り消しではないので、他で使ったトークンの成否を停止判定に使わない。

```bash
eval "$(oidc-keychain)"
oidc-add jldg
jldg-token >/dev/null
```

必要ならパスワードを入力し、再読み込み後にトークン取得と5.3の Gfarm 接続を確認する。停止しても保存済みアカウントは残り、再登録は不要である。保存済みファイルの一覧には標準の oidc-gen --accounts を使える。

### 5.6 再ログインと自動接続

再ログイン後は5.1と同じ環境設定・oidc-keychain 接続を行い、保存済みアカウントを oidc-add jldg で読み込む。

初回登録後、Bash で接続・読み込みを自動化したい利用者は、任意で `~/.bashrc` に次を追加できる。tcsh の設定例は5.7に示す。

```bash
if [[ $- == *i* && -t 0 ]]; then
    source /usr/local/jldg/jldg-env.sh
    eval "$(oidc-keychain)" >/dev/null
    if oidc-agent --status >/dev/null; then
        oidc-add jldg
    else
        printf '%s\n' 'JLDG: Could not connect to oidc-agent. Run oidc-agent --status and retry the connection steps.' >&2
    fi
fi
```

Bash のログインシェルでは `~/.bash_profile` 等から `~/.bashrc` が読み込まれることを確認する。読み込まれない構成では、このブロックをログイン時の起動ファイルに置く。複数箇所へ重複して追加しない。

自動設定では対話端末を開くと接続と読み込みを行い、新しい agent への読み込みでは暗号化パスワードを求める場合がある。バッチ実行時には読み込みを行わない。接続確認の標準エラーは隠さず、失敗時は復旧案内を表示して読み込みを省略することも確認する。新しくログインし、oidc-agent --status・oidc-add --loaded・jldg-token >/dev/null と Gfarm 接続を確認する。再認証は自動で始めず、必要なら jldg-auth を利用者が実行する。[oidc-keychain の公式説明](https://indigo-dc.github.io/oidc-agent/usage/oidc-keychain/)

同じ利用者・同じホストの agent が残っていれば共有でき、再読み込みなしで使える。OS のセッション終了設定やホスト再起動で agent が停止していたら新しく起動し、保存済みアカウントを読み込む。TMPDIR・OIDC_CONFIG_DIR 等の環境を起動時と揃える。

### 5.7 tcsh

環境設定には jldg-env.csh を使い、jldg-auth と jldg-token はコマンドとして直接実行する。5.3.6 の oidc-keychain は Bash 形式の変数設定を出力するため、その出力を tcsh で直接 eval しない。

現在の tcsh に接続先を設定するには、次のように oidc-keychain の出力を Bash で評価し、接続に必要な OIDC_SOCK を tcsh に渡す。初回起動・再接続・停止後の再開に同じ手順を使う。Bash 内部の `>/dev/null` は PID 表示が変換結果に混ざるのを防ぐために必要である。

```csh
source /usr/local/jldg/jldg-env.csh
eval `bash -c 'eval "$(oidc-keychain)" >/dev/null; printf "setenv OIDC_SOCK %q;\n" "$OIDC_SOCK"'`
printenv JWT_USER_PATH
oidc-agent --status
oidc-add jldg
jldg-token >/dev/null
echo "token status=$status"
```

初回登録・再認証が必要なら jldg-auth を直接実行する。保存済みアカウントが単に未読み込みなら oidc-add を使う。期待結果は !jldg-token と token status=0。同じ tcsh から Gfarm 接続も確認する。環境設定を再度 source しても PATH が重複せず、OIDC_SOCK 等の agent 変数を変更しないことを確認する。

初回登録後、再ログイン時の接続・読み込みを自動化したい利用者は、任意で ~/.tcshrc に次を追加できる。対話端末でのみ動作し、必要なら暗号化パスワードを入力する。

```csh
if ( $?prompt ) then
    if ( -t 0 ) then
        source /usr/local/jldg/jldg-env.csh
        eval `bash -c 'eval "$(oidc-keychain)" >/dev/null; printf "setenv OIDC_SOCK %q;\n" "$OIDC_SOCK"'`
        oidc-agent --status >/dev/null
        if ( $status == 0 ) then
            oidc-add jldg
        else
            echo 'JLDG: Could not connect to oidc-agent. Run oidc-agent --status and retry the connection steps.' >> /dev/stderr
        endif
    endif
endif
```

停止時には、次のように成功を確認してから現在の tcsh の接続用変数を解除する。oidc-keychain が出力する Bash 形式の削除コマンドは直接 eval しない。

```csh
oidc-keychain --kill
set jldg_stop_status = $status
if ( $jldg_stop_status == 0 ) then
    unsetenv OIDC_SOCK OIDCD_PID OIDCD_PID_FILE
endif
echo "stop status=$jldg_stop_status"
unset jldg_stop_status
```

停止成功時は接続用変数が解除され、JWT_USER_PATH は残ることを確認する。稼働確認には oidc-agent --status を使う。上記の変換例は標準の一時ディレクトリのソケットパスを前提とし、タブ・改行等を含む特殊なパスは対象としない。

## 6. 再認証・中断・失敗時の確認

失効試験は検証用 OP アカウントを使う。ブラウザのログアウトや agent の停止だけではリフレッシュトークンの失効を保証しない。OP 管理機能等で検証用リフレッシュトークンを失効させる。

### 6.1 更新に失敗した場合

キャッシュが利用できず、更新が必要な状態で jldg-token を実行する。失効時は非0・標準出力なしとなり、復旧候補を標準エラーに出す。キャッシュが有効なら成功し得るため、失効だけをもって直ちに失敗を期待しない。

トークン取得の失敗でブラウザ認証が自動的に始まらないことを確認する。利用者が原因を確認し、再認証が必要なら次を実行する。

```bash
jldg-auth
printf 'reauth status=%s\n' "$?"
jldg-token >/dev/null
printf 'token after reauth status=%s\n' "$?"
```

再認証の完了表示 `JLDG reauthentication completed.` と両 status=0、Gfarm 接続を確認する。未読み込みのアカウントでは、まず標準の oidc-add を使う。その読み込みで失効と案内された場合も、利用者が jldg-auth を実行する。

### 6.2 通信障害・パスワード失敗

検証環境で通信障害やパスワード誤入力を確認する。通信障害では元のエラーと復旧案内を表示し、ネットワーク復旧後に利用者が再試行する。誤入力時は再入力を求める場合があるため、キャンセル等で失敗が確定した時点で終了状態を確認する。

### 6.3 Ctrl-C と共有 agent

初回登録と再認証のパスワード入力中・ブラウザ認証待ちに Ctrl-C を押す。端末設定が戻り、`jldg-auth` が失敗終了することを確認する。共有 agent・読み込み済みアカウント・JWT_USER_PATH 等はそのまま残す。必要な復旧は利用者が選択する。SIGKILL による強制終了は端末復元の対象外である。

## 7. 障害時の切り分け

| 症状 | 主な確認箇所 |
|---|---|
| `Required command not found` | 利用者の `PATH`、パッケージと依存関係。管理者と利用者の環境差 |
| 管理者設定・クライアント設定を読めない | 配置先、権限、JLDG_AUTH_CONFIG、JLDG_CLIENT_CONFIG |
| 認証 URL が出ない・登録に失敗 | 未置換のクライアント ID、issuer・scope、OP 到達性、ローカル待受ポートの空き |
| ブラウザから OP へ接続できない | JLDG の証明書、実行ホストからの OP 到達性。手元の PC のブラウザの SOCKS5 プロキシの localhost:1080、SSH の -D 1080。名前解決エラーが出る場合は、SOCKS5 経由の名前解決設定も確認 |
| ブラウザ認証後に処理が進まない | OP に登録した URI、選択ポート。SSH の -L、ブラウザのプロキシ設定、接続先ホストの取り違え |
| 転送案内が出ない | URL の `redirect_uri` 表記。`jldg-auth` はパーセントエンコードされた `http://localhost:ポート` のみ対応 |
| Gfarm 実行中に GUI の入力要求が出る | 起動済み agent の設定、利用者側設定・service 起動オプションによる上書き、他ツールによる起動 |
| トークン取得は成功し Gfarm は失敗 | TLS・CA、XOAUTH2、issuer・audience・scope、ユーザー名の対応付け、利用権限 |
| Gfarm は成功するが jldg-token を使っていないように見える | 他認証方式へのフォールバック、`sasl_password`、`GFARM_SASL_PASSWORD`、別の環境変数設定 |
| 他端末で停止した後に接続できない | agent の共有。他端末に残った環境変数は解除されないので、利用者の標準手順で再接続・必要なら読み込み直す |
| 停止・再起動後に更新に失敗 | `pw-store`、OP のローテーション方針、利用者側の issuer 設定、ホームを共有する別ホストからの利用 |

調査記録にはコマンドのバージョン、実行ホスト、シェル、実施ケース、終了状態、必要なエラー文を残す。トークン本体、暗号化パスワード、復号したアカウント設定は記録しない。

## 8. 更新時の確認と導入完了の判定

更新後は5節・6節の手順で再確認する。同じアカウントの登録・再認証は同時に実行しない。

ホームを複数ホストで共有する場合は、暗号化ファイル・リフレッシュトークンの共有範囲を OP のローテーション方針と合わせて決め、共有ファイルの同時更新を避ける運用を用意する。

導入記録には OS・oidc-agent/Gfarm の版、配置先、検証用利用者、対象 OP・クライアントと、次の結果を残す。

- [ ] 配置・所有者・権限・構文・JSON と OP 登録値を確認した。
- [ ] 自動読み込み・自動生成・自動再認証を無効にし、利用者側設定と実際の稼働設定も確認した。
- [ ] Bash・tcsh の環境設定を読み込み、PATH が重複せず、agent 変数を変更しないことを確認した。
- [ ] 利用者の標準 agent 連携で起動・再接続・読み込み・停止を確認した。
- [ ] JLDG の証明書が設定されたブラウザで登録・再認証できた。手元の PC からの SSH 転送と SOCKS5 プロキシも確認した。
- [ ] トークン取得に失敗した場合はエラーと復旧案内が表示され、ブラウザ認証が自動で始まらなかった。
- [ ] XOAUTH2 による Gfarm のメタデータ参照・ファイル取得が成功した。
- [ ] 失効・通信障害・入力失敗・Ctrl-C と、停止後・再ログイン後の復旧を確認した。

実施できなかった項目は未確認として条件と残作業を明記する。利用者には、配置先、使用するシェルに合う環境設定・agent の接続とアカウント読み込みの方法、初回登録・再認証・停止の手順、所属拠点の問い合わせ先を案内する。
