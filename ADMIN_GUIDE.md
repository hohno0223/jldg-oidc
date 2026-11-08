# JLDG OIDC 認証補助 管理者マニュアル

本書は、実行ホストへのインストール・設定と、利用者としての動作確認の手順を示す。最短の手順は [簡易版](ADMIN_QUICKSTART.md)、jldg-auth の動作仕様とメッセージの一覧は [README](README.md) にある。利用者向けの手順は [利用手順（簡易版）](USER_QUICKSTART.md) と [ユーザマニュアル](USER_GUIDE.md) にまとめてあり、導入後に利用者へ案内する（8節）。

本書の用語：

| 用語 | 意味 |
| --- | --- |
| 実行ホスト | oidc-agent と Gfarm クライアントを実行する JLDG クライアント。利用者は手元の PC から SSH でログインする |
| OP | JLDG の OpenID Provider（認証基盤）。`https://idp.jldg.org` |
| RT | リフレッシュトークン。agent がアクセストークンの更新に使う |
| agent | 利用者ごとに動く oidc-agent |
| 暗号化パスワード | 利用者が初回登録で決める、保存済みアカウントを暗号化するパスワード |

以下の例では、スクリプトを `/usr/local/jldg` に配置する。配置先を変更する場合は、本書と利用者向け文書の操作例も合わせて読み替える。

## 1. 作業の分担と前提

| 作業 | 実行する場所・権限 |
| --- | --- |
| パッケージ導入、ファイル配置、システム設定 | 実行ホスト。管理者権限を使用 |
| OIDC クライアント登録、scope・audience の調整 | OP の管理画面等 |
| Gfarm の TLS・XOAUTH2・ユーザー名の対応付けの設定 | 対象 Gfarm の管理者がサーバー・クライアント双方で実施 |
| agent の操作、初回登録・再認証、Gfarm 接続確認 | 実行ホストへログインした検証用の一般利用者 |
| ブラウザ操作、SSH ローカル転送・SOCKS5 プロキシ | 手元の PC。JLDG ユーザ証明書をインポートしたブラウザを使う |

アカウント設定と agent は利用者ごとに管理し、各利用者が自分の OP アカウントで登録する。検証では、専用の一般利用者と、その利用者の OP アカウントを用意する。

必要なものは以下のとおりである。

- Linux、Bash 4.2 以降、`stty`、oidc-agent 5 系（`oidc-keychain`、`oidc-agent`、`oidc-gen`、`oidc-add`、`oidc-token` とパッケージの依存関係）。tcsh 利用者にも案内する場合は tcsh。
- `JWT_USER_PATH` の `!コマンド` 形式に対応した Gfarm クライアントと XOAUTH2 メカニズム。
- 実行ホストから OP への HTTPS 接続。OP への接続元はネットワーク単位で制限されているため、実行ホストが許可されたネットワークにあること。
- 手元の PC から実行ホストへの SSH ローカルポート転送と動的転送（SOCKS5 プロキシ）。手元の PC のブラウザは、このプロキシを通して OP に接続する。
- 時計が同期している実行ホスト・Gfarm サーバーと、必要な CA 証明書。

## 2. パッケージと OP の準備

### 2.1 oidc-agent と Gfarm クライアント

oidc-agent は、使用する OS に対応したパッケージと依存関係を導入する。ディストリビューションの標準パッケージが 4 系の場合は、本手順の前提を満たさない。導入元の選択は [oidc-agent 公式 Linux インストール手順](https://indigo-dc.github.io/oidc-agent/installation/install/) を参照する。

実行ホストで以下を確認する。最終的には、検証用利用者のログイン環境でも同じコマンドが見つかる必要がある。

```bash
command -v bash stty oidc-keychain oidc-agent oidc-gen oidc-add oidc-token
bash --version
oidc-agent --version
oidc-gen --version
oidc-add --version
oidc-token --version
command -v gfwhoami gfexport
```

期待結果：コマンドがすべて見つかり、Bash が 4.2 以降、oidc-agent 関連コマンドが 5 系で揃っている。tcsh の確認を行う場合は `tcsh --version` も確認する。Gfarm の導入済み版が `!コマンド` 形式に対応するかは、その版の仕様で確認する。

### 2.2 OIDC クライアント

OP に、次の条件を満たすクライアントを登録する。実際のクライアント ID、許可する scope と audience は、OP・Gfarm の管理者間で決定する。

| 項目 | 配布ファイルの設定・必要条件 |
| --- | --- |
| issuer | `https://idp.jldg.org` |
| クライアント種別 | public client。client secret を配布しない |
| フロー | authorization code flow と PKCE S256 |
| scope | `openid offline_access jldg`。RT が発行されること |
| redirect URI | 以下の5つを OP とクライアント JSON の両方へ登録 |

```text
http://localhost:4242
http://localhost:4243
http://localhost:4244
http://localhost:4245
http://localhost:4246
```

末尾の `/` の有無も含めて一致させる。oidc-agent は、実行ホストで空いているポートを候補から選ぶため、少なくとも1つが使用可能である必要がある。手元の PC でも、選ばれた同じポートと、SOCKS5 プロキシ用の1080番ポートを SSH 転送に使える必要がある。

Gfarm が検証する audience がトークンに入るよう OP を設定する。scope 名、audience、クライアント ID が同じ値になるとは限らない。`jldg-auth --token` はトークン取得時に `--aud` を指定しない。

JLDG の運用では、RT の有効期間は1か月で、更新のたびに新しい RT（そこから1か月有効）が発行される。この動作は OP 側の設定と実装によるものであり、認証補助スクリプトが設定するものではない。導入先の OP で、有効期間と更新時の再発行がこの運用と一致することを確認する。

## 3. ファイル配置と設定

更新前に、配置済みスクリプト・設定ファイル・利用者のシェル起動設定をバックアップする。

### 3.1 認証補助スクリプトと設定ファイルの配置

配布ファイルのあるディレクトリで実行する。

```bash
sudo install -d -o root -g root -m 0755 /usr/local/jldg
sudo install -o root -g root -m 0755 jldg-auth /usr/local/jldg/
sudo install -o root -g root -m 0644 jldg-env.sh jldg-env.csh /usr/local/jldg/
sudo install -d -o root -g root -m 0755 /etc/oidc-agent/issuer.config.d
sudo install -o root -g root -m 0644 jldg-auth.conf jldg-client.json /etc/oidc-agent/
sudo install -o root -g root -m 0644 issuer.config.d/jldg /etc/oidc-agent/issuer.config.d/jldg
```

配置先のファイルと親ディレクトリを、一般利用者が書き換えられないことを確認する。クライアント JSON は public client の情報であり、利用者のトークンやパスワードは書かない。

### 3.2 クライアント JSON と issuer 設定

```bash
sudoedit /etc/oidc-agent/jldg-client.json
sudoedit /etc/oidc-agent/issuer.config.d/jldg
```

`jldg-client.json` の `REPLACE_WITH_REGISTERED_JLDG_CLIENT_ID` を、登録済みのクライアント ID に変更する。issuer、scope、redirect URI は2.2節で決めた内容に合わせる。jldg-auth は JSON の構文を検査しないので、編集後に構文を確認する。

issuer 設定は次の内容を基本とする。`issuer` はクライアント JSON の `issuer_url` と一致させる。

```json
{
  "issuer": "https://idp.jldg.org",
  "pw-store": true
}
```

`pw-store` は、暗号化パスワードを agent のメモリに保持する設定である。更新された RT を暗号化アカウントファイルへ保存するために必要となる。この issuer 設定が有効なら、`oidc-add jldg` に `--pw-store` を付ける必要はない。[issuer 設定の公式説明](https://indigo-dc.github.io/oidc-agent/configuration/issuers/)

同じ issuer の設定が `/etc/oidc-agent/issuer.config` や利用者側にもある場合は、そこで `pw-store` が上書きされていないか確認する。`issuer.config.d/jldg` を配置しただけで、ほかの設定より優先されるとは限らない。

クライアント JSON を標準以外の場所に置く場合は、3.4節の `jldg-auth.conf` で `JLDG_CLIENT_CONFIG` の既定値を変更する。既存アカウントのクライアント ID や redirect URI は、この JSON を変更しただけでは更新されない。既存アカウントの変更は、OP の設定と合わせて別途計画する。

### 3.3 `/etc/oidc-agent/config`

パッケージが配置した既存の設定ファイルを編集する。

```bash
sudoedit /etc/oidc-agent/config
```

以下は既存の設定へ反映する差分であり、ファイル全体を置き換えるものではない。`oidc-agent`・`oidc-add` の該当項目を編集し、ほかの項目・セクションは残す。設定ファイルが存在しない場合は、5 系の導入状態と配布パッケージの既定設定を確認してから作業する。

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
| --- | --- |
| `auto-reauthenticate: false` | agent 自身の自動再認証を無効にする。再認証は、対話端末の jldg-auth が必要なときだけ行う |
| `autoload: false` | Gfarm のトークン要求をきっかけにアカウントを読み込まない。読み込みは対話端末の jldg-auth が行う |
| `auto-gen: false` | トークン要求をきっかけとするアカウントの自動作成を無効にする。jldg-auth による明示的な初回登録は可能 |
| `oidc-add.pw-prompt: "cli"` | アカウントの読み込みで、暗号化パスワードを端末から入力する |

そのほかは、次の既定値を基本とする。

| セクション・項目 | 値 | 確認する理由 |
| --- | --- | --- |
| `oidc-agent.webserver` | `true` | localhost で認証結果（コールバック）を受ける |
| `oidc-agent.confirm` | `false` | トークン要求ごとに確認操作を求めない |
| `oidc-agent.lifetime` | `0` | アカウントを時間経過で自動アンロードしない。トークン自体の寿命とは別 |
| `oidc-agent.group` | `null` | 同じ利用者のプロセスから使う |
| `oidc-agent.debug_logging` | `false` | 通常運用ではデバッグログを無効にする |
| `oidc-gen.default_gpg_key` | `null` | 本手順では GPG 鍵の代わりに暗号化パスワードを使う |

設定項目の基準は [公式 5.3.6 の既定設定](https://github.com/indigo-dc/oidc-agent/blob/v5.3.6/config/config) を参照する。

利用者の oidc-agent ディレクトリ内の `config` は、システム設定を上書きできる。利用者が `OIDC_USER_CONFIG` で別ファイルを指定している場合も確認する。また、システム側・利用者側の `oidc-agent-service.options` に既存の起動オプションがないか確認する。これらの設定は JLDG 以外のアカウントにも影響する。[設定の優先順位](https://indigo-dc.github.io/oidc-agent/configuration/config/)・[service の設定](https://indigo-dc.github.io/oidc-agent/usage/oidc-agent-service/)

設定は agent の起動時に読み込まれる。すでに agent を起動している利用者は、5.5節（tcsh は5.7節）の手順で停止し、5.1節の手順で起動し直して反映する。停止は同じ利用者のほかの端末にも影響するため、事前に影響を確認する。oidc-keychain は `TMPDIR` の下にある agent のソケットを探すので、停止と起動は、agent を起動したときと同じ `TMPDIR` の環境で行う。

### 3.4 `jldg-auth.conf`（oidc-gen オプション）

`/etc/oidc-agent/jldg-auth.conf` は、初回登録と再認証で oidc-gen に渡すオプションを定める Bash のファイルである。jldg-auth はこのファイルを source するので、管理者だけが編集できる権限にする。

```bash
JLDG_CLIENT_CONFIG=${JLDG_CLIENT_CONFIG:-/etc/oidc-agent/jldg-client.json}
JLDG_GEN_OPTIONS=(
    --pub --prompt=none --pw-prompt=cli --confirm-default
    --flow=code --no-scheme --no-url-call
)
```

| 項目 | 内容 |
| --- | --- |
| `JLDG_CLIENT_CONFIG` | 初回登録で使うクライアント JSON の既定のパス。利用者の環境変数でも上書きできる |
| `JLDG_GEN_OPTIONS` | oidc-gen のオプション（Bash の配列）。設定がない、配列でない、または空の場合、jldg-auth はブラウザ認証を始めずに終了する |
| `--no-url-call` | 実行ホストでブラウザを自動で開かない |
| `--flow=code --no-scheme` | localhost のコールバックで認証結果を受ける |
| `--pw-prompt=cli` | 暗号化パスワードを端末で入力する |

jldg-auth はこのファイルを、初回登録と再認証に進む場合だけ読む。読み込み・トークン取得だけで済む場合や `--token` では読まない。標準以外の場所に置く場合は、利用者の環境変数 `JLDG_AUTH_CONFIG` で指定する。

### 3.5 Gfarm の準備

Gfarm 管理者は、TLS、XOAUTH2、信頼する issuer、要求する audience・scope、JWT のユーザー識別 claim と Gfarm ユーザーとの対応を設定する。クライアントの SASL メカニズムは、検証時に `XOAUTH2` に限定する。必要な `sasl_user`、または claim からのユーザー名取得も設定する。[Gfarm 公式 SASL 認証手順](https://oss-tsukuba.org/share/doc/gfarm/html/ja/user/auth-sasl.html)

利用者の Gfarm 設定は、`GFARM_CONFIG_FILE` の指定先、未指定時は `~/.gfarm2rc` を確認し、システム設定も合わせて確認する。`GFARM_SASL_PASSWORD` や `sasl_password` が残っていると、`JWT_USER_PATH` より優先される。検証用設定から除去し、トークン取得に `jldg-auth --token` が使われるようにする。既存の秘密情報の値を端末や記録へ出力しない。[Gfarm 設定の公式説明](https://oss-tsukuba.org/share/doc/gfarm/html/ja/ref/man5/gfarm2.conf.5.html)

### 3.6 jldg-auth の動作モードと環境設定スクリプト

| 実行方法 | 用途 | 動作 |
| --- | --- | --- |
| `jldg-auth` | 利用者が対話端末で実行する利用準備 | 未登録なら初回登録、登録済みなら読み込みとトークン取得の確認。OP が RT を無効と返した場合だけブラウザ再認証へ進む |
| `jldg-auth --no-browser` | シェル起動時の自動準備など | 読み込みとトークン取得の確認だけを行う。未登録・RT 無効の場合は、引数なしの jldg-auth を案内して非0で終了する |
| `jldg-auth --token` | Gfarm が `JWT_USER_PATH` から実行する | トークンを標準出力に返すだけで、読み込みやブラウザ認証は行わない |

引数なしと `--no-browser` は、暗号化パスワードを求める場合があるため対話端末で使う。非対話の環境からは開始しない。詳細な動作と、表示されるメッセージの一覧は [README](README.md) を参照する。

環境設定スクリプト（`jldg-env.sh`・`jldg-env.csh`）は、配置先を `PATH` に加え、`JWT_USER_PATH` を `!jldg-auth --token` に設定する。agent の操作は行わない。配置先を変更した場合は、利用者が source の前に環境変数 `JLDG_HELPER_DIR` にそのパスを設定する（既定は `/usr/local/jldg`）。

## 4. インストール後の静的確認

実行ホスト上で、agent を起動せずに確認する。

```bash
ls -ld /usr/local/jldg /etc/oidc-agent /etc/oidc-agent/issuer.config.d
ls -l /usr/local/jldg/jldg-auth
ls -l /usr/local/jldg/jldg-env.sh /usr/local/jldg/jldg-env.csh
ls -l /etc/oidc-agent/jldg-auth.conf /etc/oidc-agent/jldg-client.json
(
    for jldg_script in jldg-auth jldg-env.sh; do
        bash -n "/usr/local/jldg/$jldg_script" || exit
    done
    bash -n /etc/oidc-agent/jldg-auth.conf
)
```

配置したファイルが root 所有で、jldg-auth は実行可能、環境設定スクリプトと管理者設定は一般利用者が読めることを確認する。tcsh 用の環境設定スクリプトは、5.7節で実際に source して確認する。

あわせて次を確認する。

- クライアント JSON の構文と必須項目、クライアント ID が置き換え済みであること、issuer・scope・redirect URI が OP の登録と一致すること。
- issuer 設定の `pw-store` が `true`、`oidc-add` の `pw-prompt` が `cli` であること。
- 利用者側の設定や service の起動オプションによる上書きがないこと。

## 5. 利用者としての動作確認

専用の一般利用者でログインして確認する。5.7節以外は Bash を使う。実際のトークンを出力するコマンドには `>/dev/null` を付ける。

### 5.1 環境設定・agent への接続・初回登録

```bash
source /usr/local/jldg/jldg-env.sh
command -v jldg-auth
printenv JWT_USER_PATH
eval "$(oidc-keychain)"
oidc-agent --status
oidc-gen --accounts
```

期待結果：jldg-auth が配置先から見つかり、`JWT_USER_PATH` が `!jldg-auth --token` で、`oidc-agent --status` で接続を確認できる。oidc-keychain は、同じ利用者・同じホストの agent が動いていれば接続し、なければ起動する。初回の起動も再接続も、この手順を使う。

`oidc-agent --status` の表示で、稼働中の agent が 5 系であり、Autoload と Auto Re-authenticate が false、Webserver が true、Confirm が false であることを確認する。auto-gen は設定ファイルで確認する。項目の表記は導入した版に従う。

`jldg` が未登録の検証用利用者で、初回登録を確認する。

```bash
jldg-auth
printf 'register status=%s\n' "$?"
```

認証 URL と `Browser authentication:` で始まる案内が表示されたら、元の端末は待機させ、手元の PC で次の操作を行う。

1. 新しい端末を開き、実行ホストへの SSH 転送を開始する。コールバック用ポートが4243の例：

   ```bash
   ssh -N -o ExitOnForwardFailure=yes -L 4243:localhost:4243 -D 1080 YOUR_SSH_HOST_ALIAS
   ```

   接続先は実際の実行ホストに置き換え、鍵・踏み台等は普段の指定を使う。`-L` のポートは、URL と案内に表示されたものに合わせる。`-D` は OP への接続に、`-L` は localhost コールバックに使う。両方のポートが PC 側で使用可能であることを確認する。

2. JLDG ユーザ証明書をインポートしたブラウザで SOCKS5 プロキシを `localhost:1080` に設定し、SSH を維持したまま認証 URL を開いて認証する。
3. 元の端末が `Please press Enter to try it again.` で待っている場合は、ブラウザ認証が完了してから Enter を押す。OP の認証セッションが期限切れになった場合は、jldg-auth を再実行する。
4. 元の端末の表示に従い、暗号化パスワードを設定する。
5. 処理が終わったら、プロキシを元に戻し、転送を Ctrl-C で終了する。

期待結果：認証 URL・転送案内・パスワード入力案内が表示され、案内のポートが URL のポートと一致する。`JLDG account registration completed.` に続いて `JLDG is ready.` が表示され、`register status=0` となる。jldg-auth は登録後にトークンの取得まで確認している。

### 5.2 アカウントとトークン取得

```bash
oidc-add --loaded
jldg-auth --token >/dev/null
printf 'token status=%s\n' "$?"
```

期待結果：`jldg` が読み込み済みで、`token status=0` となる。取得に失敗した場合は非0となり、元のエラーと復旧の案内が標準エラーに表示される。

jldg-auth は `oidc-token --time=60 jldg` でトークンを取得する。`--time=60` は残り有効時間の要求であり、トークンの寿命を60秒にする指定ではない。有効なキャッシュがあればそれを返し、必要なら agent が通常の更新を行う。[oidc-token の仕様](https://indigo-dc.github.io/oidc-agent/usage/oidc-token/options/)

RT の期限の起点は、最後に新しい RT が発行された時点（初回認証または最後の更新）である。キャッシュされたアクセストークンを返すだけでは RT は更新されず、期限も延びない。個々の RT の期限日時は通常の手順では表示されず、`oidc-token --expires-at` が表示するのはアクセストークンの期限である。現在 RT で更新できるかを確認するには、5.4節の手順を使う。

暗号化ファイルの保存先は、通常 `~/.config/oidc-agent` または `~/.oidc-agent`、`OIDC_CONFIG_DIR` を指定した場合はそのディレクトリである。利用者本人の所有とし、ディレクトリ0700・アカウントファイル0600を基本とする。内容を表示する必要はない。[公式説明](https://indigo-dc.github.io/oidc-agent/configuration/directory/)

### 5.3 Gfarm 接続

```bash
JLDG_TEST_FILE='gfarm:///REPLACE_WITH_TEST_FILE'
gfwhoami
printf 'gfwhoami status=%s\n' "$?"
gfexport "$JLDG_TEST_FILE" >/dev/null
printf 'gfexport status=%s\n' "$?"
```

ファイルのパスは実際の検証用パスに置き換える。`gfwhoami` が検証用利用者の Gfarm ユーザー名を表示し、ファイル取得が成功して、両方の status が0となることを確認する。

成功しただけでは、sharedsecret・GSI 等の別方式や、`sasl_password` 等の別のトークン設定が使われた可能性を除外できない。他方式へのフォールバックを無効にするか、ログで XOAUTH2 が使われたことも確認する。

### 5.4 保存済みアカウントの読み込みと更新確認

新しい agent では、jldg-auth が内部で `oidc-add jldg` を実行してアカウントを読み込む。まだ読み込まれていないアカウントの読み込みでは、oidc-add が OP のメタデータ取得と RT による更新を行うため、RT の失効がここで判明する場合がある。読み込み済みなら、oidc-add は更新を省略する。

```bash
jldg-auth
jldg-auth --token >/dev/null
printf 'loaded token status=%s\n' "$?"
oidc-token --force-new jldg >/dev/null
printf 'refresh status=%s\n' "$?"
```

必要なら暗号化パスワードを入力し、正常なアカウントではブラウザ認証なしで成功することを確認する。`jldg-auth --token` は有効なキャッシュを返す場合があるため、その成功だけでは RT を現在利用できるかは分からない。

`--force-new` はキャッシュを使わず、OP へ新しいアクセストークンを要求する。つまり、読み込み済みの RT で実際に更新を試す。`refresh status=0` ならその時点で更新できるが、将来の期限を確認する操作ではない。更新された RT が保存されることは、5.5節の停止・再読み込みの後にトークン取得が成功することで確認する。

通信障害、agent への未接続、アカウントの未読み込みでも失敗するため、更新に失敗しただけでは RT の期限切れとは断定しない。OP から RT が無効との応答がある場合は、6.1節の手順で再認証する。

CLI での入力とパスワードの保持は、3節の管理者設定による。`--pw-prompt=cli`・`--pw-store` を省略しても、必要な入力が端末に表示されることを確認する。

本手順では、oidc-keychain に `--accounts jldg` を付けない。oidc-keychain 5.3.6 は、`oidc-prompt` が見つかると内部の oidc-add に `--pw-prompt=gui` を付け、CLI の既定値を上書きするためである。これはその内部呼び出しだけに適用され、以降の手動の oidc-add の既定値は変えない。そのため、agent への接続（oidc-keychain）と読み込み（jldg-auth）を分けている。[5.3.6 の実装](https://github.com/indigo-dc/oidc-agent/blob/v5.3.6/src/oidc-keychain/oidc-keychain)

### 5.5 停止と再読み込み

agent を停止する前に、同じ利用者の共有 agent を使うほかの端末・ほかのアカウントへの影響を確認する。Bash での通常の停止操作は `eval "$(oidc-keychain --kill)"` である。これで agent が停止し、現在のシェルの接続用変数も解除される。

検証では、停止処理自体の終了状態も確認するため、出力を変数に受け取り、成功したときだけ評価する。単に eval の終了状態を見ると、停止処理の失敗を見落とす場合がある。

```bash
jldg_stop_commands=$(oidc-keychain --kill)
jldg_stop_status=$?
if (( jldg_stop_status == 0 )); then
    eval "$jldg_stop_commands"
    jldg_stop_status=$?
fi
printf 'stop status=%s\n' "$jldg_stop_status"
unset jldg_stop_commands jldg_stop_status
jldg-auth --token >/dev/null
printf 'stopped token status=%s\n' "$?"
printenv JWT_USER_PATH
```

期待結果：

- `stop status=0` で、現在のシェルの `OIDC_SOCK`・`OIDCD_PID`・`OIDCD_PID_FILE` が解除される。ほかの端末の接続用変数は変更されない。
- トークン取得は非0となり、標準エラーに復旧の案内が表示される。
- `JWT_USER_PATH` は `!jldg-auth --token` のまま残る。

stop status が非0なら、停止処理のエラーを確認する。停止は発行済みトークンの取り消しではないので、ほかで使ったトークンの成否を停止の判定に使わない。

続いて再開する。

```bash
eval "$(oidc-keychain)"
jldg-auth
jldg-auth --token >/dev/null
```

必要ならパスワードを入力し、再読み込み後のトークン取得と、5.3節の Gfarm 接続を確認する。停止しても保存済みアカウントは残り、再登録は不要である。保存済みファイルの一覧は `oidc-gen --accounts` で確認できる。

### 5.6 再ログインと自動準備

再ログイン後は、5.1節と同じ環境設定と oidc-keychain による接続を行い、jldg-auth で保存済みアカウントを準備する。

同じ利用者・同じホストの agent が残っていれば共有でき、読み込み直さずに使える。OS のセッション終了設定やホストの再起動で agent が停止していれば、新しく起動し、保存済みアカウントを読み込む。`TMPDIR`・`OIDC_CONFIG_DIR` 等の環境は、起動時と揃える。

初回登録後、接続と読み込みを自動化したい利用者は、任意で `~/.bashrc` に次を追加できる。tcsh の設定例は5.7節に示す。利用者向けの説明は [ユーザマニュアル](USER_GUIDE.md) の8節にある。

```bash
if [[ $- == *i* && -t 0 ]]; then
    source /usr/local/jldg/jldg-env.sh
    eval "$(oidc-keychain)" >/dev/null
    if oidc-agent --status >/dev/null; then
        jldg-auth --no-browser
    else
        printf '%s\n' 'JLDG: Could not connect to oidc-agent. Run oidc-keychain.' >&2
    fi
fi
```

Bash のログインシェルでは、`~/.bash_profile` 等から `~/.bashrc` が読み込まれることを確認する。読み込まれない構成では、このブロックをログイン時の起動ファイルに置く。複数箇所へ重複して追加しない。

この設定例の動作として、次を確認する。

- 対話端末を開くと接続と読み込みを行い、新しい agent への読み込みでは暗号化パスワードを求める場合がある。バッチ実行時には何もしない。
- 接続確認の標準エラーは隠さず、接続に失敗したら案内を表示して読み込みを省略する。
- `--no-browser` を使うため、初回登録・ブラウザ再認証は始めず、必要な場合は引数なしの jldg-auth を案内する。
- 新しくログインし、`oidc-agent --status`・`oidc-add --loaded`・`jldg-auth --token >/dev/null` と Gfarm 接続が成功する。

ログイン時にもブラウザ再認証を許可したい利用者だけ、起動設定の `jldg-auth --no-browser` を `jldg-auth` に変更する。この場合、新しい SSH 接続や tmux のペインなどでも起動設定が実行され、再認証が必要なときは認証待ちになる。Gfarm やバッチから呼ばれる `--token` は、どちらの場合もブラウザ認証を始めない。[oidc-keychain の公式説明](https://indigo-dc.github.io/oidc-agent/usage/oidc-keychain/)

### 5.7 tcsh

環境設定には `jldg-env.csh` を使う。jldg-auth はコマンドとして直接実行し、取得だけを確認する場合は `--token` を付ける。oidc-keychain 5.3.6 は Bash 形式の変数設定を出力するため、その出力を tcsh で直接 eval しない。

現在の tcsh に接続先を設定するには、次のように oidc-keychain の出力を Bash で評価し、接続に必要な `OIDC_SOCK` だけを tcsh に渡す。初回の起動・再接続・停止後の再開に、同じ手順を使う。Bash 内部の `>/dev/null` は、PID の表示が変換結果に混ざるのを防ぐために必要である。

```csh
source /usr/local/jldg/jldg-env.csh
eval `bash -c 'eval "$(oidc-keychain)" >/dev/null; printf "setenv OIDC_SOCK %q;\n" "$OIDC_SOCK"'`
printenv JWT_USER_PATH
oidc-agent --status
jldg-auth
jldg-auth --token >/dev/null
echo "token status=$status"
```

期待結果は `!jldg-auth --token` と `token status=0` である。同じ tcsh から Gfarm 接続も確認する。環境設定を再度 source しても PATH が重複せず、`OIDC_SOCK` 等の agent の変数が変更されないことも確認する。上記の変換例は標準の一時ディレクトリのソケットパスを前提とし、タブ・改行等を含む特殊なパスは対象としない。

初回登録後、再ログイン時の接続・読み込みを自動化したい利用者は、任意で `~/.tcshrc` に次を追加できる。動作は5.6節の Bash の例と同じである。

```csh
if ( $?prompt ) then
    if ( -t 0 ) then
        source /usr/local/jldg/jldg-env.csh
        eval `bash -c 'eval "$(oidc-keychain)" >/dev/null; printf "setenv OIDC_SOCK %q;\n" "$OIDC_SOCK"'`
        oidc-agent --status >/dev/null
        if ( $status == 0 ) then
            jldg-auth --no-browser
        else
            echo 'JLDG: Could not connect to oidc-agent. Run oidc-keychain.' >> /dev/stderr
        endif
    endif
endif
```

停止するときは、次のように成功を確認してから、現在の tcsh の接続用変数を解除する。oidc-keychain が出力する Bash 形式の削除コマンドは、直接 eval しない。

```csh
oidc-keychain --kill
set jldg_stop_status = $status
if ( $jldg_stop_status == 0 ) then
    unsetenv OIDC_SOCK OIDCD_PID OIDCD_PID_FILE
endif
echo "stop status=$jldg_stop_status"
unset jldg_stop_status
```

停止に成功すると接続用変数が解除され、`JWT_USER_PATH` は残ることを確認する。稼働状況の確認には `oidc-agent --status` を使う。

## 6. 再認証と失敗時の確認

失効の試験には、検証用の OP アカウントを使う。ブラウザでのログアウトや agent の停止だけでは、RT の失効は保証されない。OP の管理機能等で、検証用の RT を失効させる。

### 6.1 更新に失敗した場合

アクセストークンのキャッシュが使えず更新が必要な状態で、`jldg-auth --token >/dev/null` を実行する。

期待結果：失効時は非0で、標準出力は空となる。OP のエラーはそのまま表示され、oidc-agent 標準の再認証案内（`oidc-gen jldg --reauthenticate`）の代わりに `JLDG reauthentication is required. Run in a terminal: jldg-auth` が表示される。ブラウザ認証は始まらない。キャッシュが有効な間は成功し得るため、失効させた直後に失敗するとは限らない。

続いて、対話端末で次を実行する。

```bash
jldg-auth
printf 'prepare status=%s\n' "$?"
jldg-auth --token >/dev/null
printf 'token after prepare status=%s\n' "$?"
```

期待結果：

- 未読み込みのアカウントの読み込み時と、読み込み済みアカウントのトークン取得時の両方で、RT の無効が判明した場合だけ、`The refresh token was rejected. Starting JLDG browser reauthentication.` から再認証へ進む。
- `JLDG reauthentication completed.` に続いて `JLDG is ready.` が表示され、両方の status が0で、Gfarm にも接続できる。
- 正常なアカウントで jldg-auth を繰り返しても、ブラウザ認証は繰り返されない。
- 再認証後のトークン取得に失敗した場合は `JLDG is ready.` を表示せず、自動で再認証を繰り返さない。再認証自体が失敗した場合は `JLDG reauthentication did not complete.` と再実行の案内が表示される。

### 6.2 通信障害・パスワード入力の失敗

検証環境で、OP の停止・通信障害・タイムアウトを確認する。失敗時は非0となり、元のエラーと復旧の案内を表示し、ブラウザ再認証や agent の再起動には進まない。復旧後に jldg-auth を再実行する。

パスワード入力後に `Error: the other party disconnected` が出た場合は、agent との IPC 通信が切れている。jldg-auth が agent への接続を再確認し、接続できるかどうかで案内を分けることを確認する。この文言だけで、OP の停止・パスワード誤り・RT の失効のいずれとも断定しない。読み込み処理の完了を確認できないため、読み込み一覧に載っているだけで成功とはしない。

パスワードを誤入力すると再入力を求められる場合があるため、キャンセル等で失敗が確定した時点で終了状態を確認する。既知の RT 拒否以外のエラーや、単に `--reauthenticate` という語を含むだけの診断では、再認証に進まないことも確認する。

### 6.3 Ctrl-C と共有 agent

通常の読み込み・初回登録・再認証のパスワード入力中と、ブラウザ認証の待機中に Ctrl-C を押す。端末設定が元に戻り、jldg-auth が非0で終了することを確認する。jldg-auth 自身は共有 agent を停止せず、アカウントを削除・アンロードせず、環境変数を変更しない。失敗後の読み込み状態は別途確認する。SIGKILL は端末設定の復元の対象外である。

### 6.4 シェル起動時の自動準備

5.6節・5.7節の設定例について、次を確認する。

- 正常時は、`--no-browser` で読み込みとトークン取得の確認が成功する。
- 未登録、読み込み時の失効、取得時の失効では、非0・標準出力なしで、手動の jldg-auth を案内する。初回登録・再認証は始めず、`jldg-auth.conf` も読まない。
- 起動設定を引数なしの jldg-auth に変更した場合だけ、必要なときにブラウザ認証へ進む。
- 非対話シェルでは起動設定を実行しない。準備モードを非対話で直接呼んだ場合も認証は始めない。
- シェル起動時の失敗で、ログインシェル自体が終了しない。

## 7. 障害時の切り分け

| 症状 | 主な確認箇所 |
| --- | --- |
| `Required command not found` | 利用者の `PATH`、パッケージと依存関係。管理者と利用者の環境差 |
| `Cannot read administrator configuration`、`Cannot read client configuration` | 配置先、権限、`JLDG_AUTH_CONFIG`、`JLDG_CLIENT_CONFIG` |
| `JLDG_GEN_OPTIONS is not set as an array` | `jldg-auth.conf` の `JLDG_GEN_OPTIONS=( ... )` の記述 |
| `Cannot connect to oidc-agent.` | 利用者の agent の起動状況と `OIDC_SOCK`。oidc-keychain で接続し直す |
| `JLDG: Communication with oidc-agent was interrupted` | agent の接続・プロセスの状態と OP への到達性。jldg-auth の再確認結果に従う。パスワード誤り・失効とは断定しない |
| 認証 URL が出ない・登録に失敗する | 置き換えていないクライアント ID、issuer・scope、OP への到達性、ローカル待受ポートの空き |
| ブラウザから OP へ接続できない | JLDG ユーザ証明書、実行ホストからの OP への到達性。ブラウザの SOCKS5 プロキシが `localhost:1080` か、SSH に `-D 1080` があるか。名前解決エラーが出る場合は、SOCKS5 経由の名前解決設定も確認 |
| ブラウザ認証後に処理が進まない | OP に登録した URI、選択されたポート、SSH の `-L`、ブラウザのプロキシ設定、接続先ホストの取り違え |
| `JLDG account registration did not complete.`、`JLDG reauthentication did not complete.` | 直前の oidc-gen のエラー。Enter を押す時機、OP の認証セッションの期限、転送とプロキシの設定 |
| 転送案内（`Browser authentication:`）が出ない | URL の `redirect_uri` の表記。jldg-auth はパーセントエンコードされた `http://localhost:ポート` だけに対応 |
| Gfarm の実行中に GUI の入力要求が出る | 起動済み agent の設定、利用者側設定・service の起動オプションによる上書き、ほかのツールによる起動 |
| トークン取得は成功し Gfarm は失敗する | TLS・CA、XOAUTH2、issuer・audience・scope、ユーザー名の対応付け、利用権限 |
| Gfarm は成功するが jldg-auth --token を使っていないように見える | ほかの認証方式へのフォールバック、`sasl_password`、`GFARM_SASL_PASSWORD`、別の環境変数設定 |
| ほかの端末で停止した後に接続できない | agent の共有。ほかの端末に残った環境変数は解除されないので、利用者の標準手順で接続し直し、必要なら読み込み直す |
| 停止・再起動後に更新に失敗する | `pw-store`、OP の RT ローテーション方針、利用者側の issuer 設定、ホームを共有する別ホストからの利用 |

jldg-auth が表示するメッセージの一覧は [README](README.md) にある。調査記録には、コマンドのバージョン、実行ホスト、シェル、実施したケース、終了状態、必要なエラー文を残す。トークン本体、暗号化パスワード、復号したアカウント設定は記録しない。

## 8. 更新時の確認と導入完了の判定

更新後は、5節・6節の手順で再確認する。

更新で `JWT_USER_PATH` の値が変わる場合、すでに開いている利用者のシェルには反映されない。利用者に、環境設定を再度 source するか、ログインし直すよう案内する。環境設定は何度 source しても PATH が重複しない。

同じアカウントの初回登録・ブラウザ再認証は、複数の端末から同時に実行しない。認証処理や設定の保存が競合し、やり直しが必要になる場合がある。

ホームを複数ホストで共有する場合は、暗号化ファイルと RT の共有範囲を OP のローテーション方針と合わせて決め、共有ファイルの同時更新を避ける運用を用意する。

導入記録には、OS・oidc-agent/Gfarm の版、配置先、検証用利用者、対象の OP・クライアントと、次の結果を残す。

- [ ] 配置・所有者・権限・構文・JSON と OP の登録値を確認した。
- [ ] 自動読み込み・自動生成・自動再認証を無効にし、利用者側の設定と実際の稼働設定も確認した。
- [ ] Bash・tcsh の環境設定を読み込み、PATH が重複せず、agent の変数を変更しないことを確認した。
- [ ] oidc-keychain による起動・再接続・停止と、jldg-auth による読み込みを確認した。
- [ ] JLDG ユーザ証明書をインポートしたブラウザで、登録・再認証できた。手元の PC からの SSH 転送と SOCKS5 プロキシも確認した。
- [ ] `--token` の失敗時はエラーと復旧の案内を表示し、ブラウザ認証を始めなかった。
- [ ] 対話端末の jldg-auth は、正常時に再認証せず、RT 拒否時だけ再認証した。
- [ ] XOAUTH2 による Gfarm のメタデータ参照・ファイル取得が成功した。
- [ ] 失効・通信障害・入力失敗・Ctrl-C と、停止後・再ログイン後の復旧を確認した。

実施できなかった項目は、未確認として条件と残作業を明記する。

利用者には、[利用手順（簡易版）](USER_QUICKSTART.md) と [ユーザマニュアル](USER_GUIDE.md) を配布する。配置先が `/usr/local/jldg` と異なる場合は、その配置先と `JLDG_HELPER_DIR` の設定方法を添える。あわせて、利用者が使うシェル、所属拠点の問い合わせ先も案内する。
