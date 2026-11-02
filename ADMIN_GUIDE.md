# JLDG oidc-agent helper 管理者マニュアル

本書は、実行ホストへのインストールと、利用者としての動作確認を行う手順を示す。利用者に案内する開始・停止・SSH 転送の手順は [README.md](README.md) を参照する。

以下の例ではスクリプトを `/usr/local/share/jldg` に配置する。配置先を変更する場合は、本書と利用者向けの操作例を合わせて変更する。

## 1. 作業の分担と前提

| 作業 | 実行する場所・権限 |
|---|---|
| パッケージ導入、ファイル配置、システム設定 | oidc-agent と Gfarm クライアントを実行する Linux ホスト。管理者権限を使用 |
| OIDC クライアント登録、scope・audience の調整 | JLDG の OpenID Provider（OP）の管理画面等 |
| Gfarm の TLS・XOAUTH2・ユーザー対応の設定 | 対象 Gfarm の管理者がサーバー・クライアント双方で実施 |
| 初回登録、開始・停止、トークン取得、Gfarm 接続確認 | Linux ホストへログインした検証用の一般利用者。`sudo` を付けない |
| ブラウザ操作 | 実行ホストまたは別 PC。JLDG の証明書がインストールされたブラウザを使う |
| SSH ローカル転送・SOCKS proxy | 別 PC のブラウザを使う場合に、その PC で設定 |

アカウント設定と agent は利用者ごとに管理する。管理者が root として登録した `jldg` アカウントを利用者へ配布する手順ではない。検証では専用の一般利用者と、その利用者の OP アカウントを用意する。

必要なものは以下のとおりである。

- Linux、Bash、oidc-agent 5 系。tcsh 利用者にも案内する場合は tcsh。
- `oidc-agent-service`、`oidc-agent`、`oidc-gen`、`oidc-add`、`oidc-token` と、それらのパッケージ依存関係。
- スクリプトが使う `grep`、`tee`、`cat`、`dirname` 等の標準コマンド。本書の静的確認には Python 3 も使用する。
- `JWT_USER_PATH` の `!コマンド` 形式に対応した Gfarm クライアントと XOAUTH2 メカニズム。
- 実行ホストから OP への HTTPS 接続と、JLDG の証明書がインストールされたブラウザ。
- 別 PC のブラウザを使う場合は、PC から実行ホストへの SSH ローカルポート転送と動的転送（SOCKS5 proxy）。ブラウザから OP へはこの proxy を通して接続する。同じマシンのブラウザを使う場合は、この SSH 転送は不要。
- 時計が同期している実行ホスト・Gfarm サーバーと、必要な CA 証明書。

## 2. パッケージと OP の準備

### 2.1 oidc-agent と Gfarm クライアント

oidc-agent は、使用する OS に対応したパッケージと依存関係を導入する。ディストリビューションの標準パッケージが 4 系の場合は、本手順の前提を満たさない。導入元の選択は [oidc-agent 公式 Linux インストール手順](https://indigo-dc.github.io/oidc-agent/installation/install/) を参照する。

実行ホストで以下を確認する。最終的には検証用利用者のログイン環境でも同じコマンドが見つかる必要がある。

```bash
command -v bash oidc-agent-service oidc-agent oidc-gen oidc-add oidc-token grep tee cat dirname
oidc-agent --version
oidc-gen --version
oidc-add --version
oidc-token --version
command -v gfls gfexport python3
```

期待結果：コマンドがすべて見つかり、oidc-agent 関連コマンドが 5 系で揃っている。tcsh の確認を行う場合は `tcsh --version` も確認する。Gfarm の導入済み版が `!コマンド` 形式に対応するかは、その版の仕様で確認する。

### 2.2 OIDC クライアント

OP に、次の条件を満たすクライアントを登録する。実際の client ID、許可する scope と audience は OP・Gfarm の管理者間で決定する。

| 項目 | 配布ファイルの設定・必要条件 |
|---|---|
| issuer | `https://idp.jldg.org` |
| クライアント種別 | public client。client secret を配布しない |
| フロー | authorization code flow と PKCE S256 |
| scope | `openid offline_access jldg`。refresh token が発行されること |
| redirect URI | 以下の5つを OP とクライアント JSON の両方へ登録 |

```text
http://localhost:4242
http://localhost:4243
http://localhost:4244
http://localhost:4245
http://localhost:4246
```

末尾の `/` の有無も含めて一致させる。oidc-agent が利用できる候補を選ぶため、実行ホスト側で少なくとも1つのポートが使用可能である必要がある。別 PC のブラウザを使う場合は、PC 側でも選択された同じポートと SOCKS proxy 用の1080番ポートを SSH 転送に使える必要がある。

Gfarm が検証する audience がトークンに入るよう OP を設定する。scope 名と audience、client ID が同じ値になるとは限らない。本スクリプトはトークン取得時に `--aud` を指定しない。

## 3. ファイル配置と設定

更新作業の場合は、先に配置先の3スクリプト、クライアント JSON、issuer 設定、`/etc/oidc-agent/config` をバックアップする。既存 agent の停止は、同じ利用者の他端末・他アカウントにも影響するので利用時間を調整する。

### 3.1 helper と設定ファイルの配置

配布ファイルのあるディレクトリで実行する。

```bash
sudo install -d -o root -g root -m 0755 /usr/local/share/jldg
sudo install -o root -g root -m 0755 jldg-agent.sh jldg-agent.csh jldg-agent-core.sh /usr/local/share/jldg/
sudo install -d -o root -g root -m 0755 /etc/oidc-agent/issuer.config.d
sudo install -o root -g root -m 0644 jldg-client.json /etc/oidc-agent/jldg-client.json
sudo install -o root -g root -m 0644 issuer.config.d/jldg /etc/oidc-agent/issuer.config.d/jldg
```

3スクリプトは必ず同じディレクトリに置く。配置先ファイルと親ディレクトリを一般利用者が書き換えられないことを確認する。クライアント JSON は public client の情報であり、利用者のトークンやパスワードを記入しない。

### 3.2 クライアント JSON と issuer 設定

```bash
sudoedit /etc/oidc-agent/jldg-client.json
sudoedit /etc/oidc-agent/issuer.config.d/jldg
```

`jldg-client.json` の `REPLACE_WITH_REGISTERED_JLDG_CLIENT_ID` を登録済みの client ID に変更する。issuer、scope、redirect URI は前節で決定した内容に合わせる。

issuer 設定は次の内容を基本とする。`issuer` はクライアント JSON の `issuer_url` と一致させる。

```json
{
  "issuer": "https://idp.jldg.org",
  "pw-store": true
}
```

`pw-store` は、更新された refresh token を暗号化アカウントファイルへ保存するために、暗号化パスワードを agent のメモリに保持する設定である。平文パスワードファイルは作成しない。保存済みアカウントの読み込みには、スクリプトが `oidc-add --pw-store` も指定する。[issuer 設定の公式説明](https://indigo-dc.github.io/oidc-agent/configuration/issuers/)

同じ issuer の設定が `/etc/oidc-agent/issuer.config` や利用者側にも存在する場合は、そこで `pw-store` が上書きされていないか確認する。`issuer.config.d/jldg` を配置しただけで他の設定より優先されるとは限らない。

標準のクライアント JSON の配置先を変える場合のみ、利用者の環境変数 `JLDG_CLIENT_CONFIG` にそのパスを指定する。既存アカウントの client ID や redirect URI は、この JSON を変更しただけでは更新されない。既存アカウントの変更は OP の設定と合わせて別途計画する。

### 3.3 `/etc/oidc-agent/config`

パッケージが配置した既存の設定ファイルを編集する。

```bash
sudoedit /etc/oidc-agent/config
```

以下は既存設定へ反映する差分であり、ファイル全体を置き換えるものではない。`oidc-gen`、`oidc-add`、`oidc-token` 等の他のセクションも残す。設定ファイルが存在しない場合は、5 系の導入状態と配布パッケージの既定設定を確認してから作業する。

```json
{
  "oidc-agent": {
    "auto-reauthenticate": false,
    "autoload": false,
    "auto-gen": false
  }
}
```

| 設定 | 運用上の意味 |
|---|---|
| `auto-reauthenticate: false` | agent は自動で再認証を始めず、`start` が端末上で再認証を扱う |
| `autoload: false` | トークン要求時の自動読み込みを無効にし、未読み込み時は `start` で復旧する |
| `auto-gen: false` | トークン要求をきっかけとする設定の自動作成を無効にする。`start` が明示的に実行する初回登録は可能 |

その他は次の既定値を基本とする。

| セクション・項目 | 値 | 確認する理由 |
|---|---|---|
| `oidc-agent.webserver` | `true` | localhost コールバックを受ける |
| `oidc-agent.confirm` | `false` | トークン要求ごとに確認操作を求めない |
| `oidc-agent.lifetime` | `0` | アカウントを時間経過で自動アンロードしない。トークン自体の寿命とは別 |
| `oidc-agent.group` | `null` | 同じ利用者のプロセスから使う |
| `oidc-agent.debug_logging` | `false` | 通常運用ではデバッグログを無効にする |
| `oidc-gen.default_gpg_key` | `null` | 本手順では GPG 鍵の代わりに暗号化パスワードを使う |

`--no-scheme`、`--no-url-call`、CLI 入力方式、パスワード保持、`--time=60` はスクリプトで指定するため、同じ目的の全体設定を追加する必要はない。設定項目の基準は [公式 5.3.6 の既定設定](https://github.com/indigo-dc/oidc-agent/blob/v5.3.6/config/config) を参照する。

利用者の oidc-agent ディレクトリ内の `config` はシステム設定を上書きできる。利用者が `OIDC_USER_CONFIG` で別ファイルを指定している場合も確認する。また、システム側・利用者側の `oidc-agent-service.options` に既存の起動オプションがないか確認する。これらの設定は JLDG 以外のアカウントにも影響する。[設定の優先順位](https://indigo-dc.github.io/oidc-agent/configuration/config/)・[service の設定](https://indigo-dc.github.io/oidc-agent/usage/oidc-agent-service/)

設定を変えても、起動済み agent の動作はそのままである。利用者として `stop` と `start` を順に実行して反映する。スクリプトは起動済み agent の設定を検査しない。

### 3.4 Gfarm の準備

Gfarm 管理者は TLS、XOAUTH2、信頼する issuer、要求する audience・scope、JWT のユーザー識別 claim と Gfarm ユーザーとの対応を設定する。クライアントの SASL メカニズムは検証時に `XOAUTH2` に限定する。必要な `sasl_user`、または claim からのユーザー名取得も設定する。[Gfarm 公式 SASL 認証手順](https://oss-tsukuba.org/share/doc/gfarm/html/ja/user/auth-sasl.html)

利用者の Gfarm 設定は `GFARM_CONFIG_FILE` の指定先、未指定時は `~/.gfarm2rc` を確認し、システム設定も合わせて確認する。`GFARM_SASL_PASSWORD` や `sasl_password` が残っていると `JWT_USER_PATH` より優先される。検証用設定から除去し、トークン取得経路が本 helper になるようにする。既存の秘密情報の値を端末や記録へ出力しない。[Gfarm 設定の公式説明](https://oss-tsukuba.org/share/doc/gfarm/html/ja/ref/man5/gfarm2.conf.5.html)

## 4. インストール後の静的確認

実行ホスト上で行う。この節では agent を起動しない。

```bash
ls -ld /usr/local/share/jldg /etc/oidc-agent /etc/oidc-agent/issuer.config.d
ls -l /usr/local/share/jldg/jldg-agent.sh /usr/local/share/jldg/jldg-agent.csh /usr/local/share/jldg/jldg-agent-core.sh
ls -l /etc/oidc-agent/config /etc/oidc-agent/jldg-client.json /etc/oidc-agent/issuer.config.d/jldg
bash -n /usr/local/share/jldg/jldg-agent.sh /usr/local/share/jldg/jldg-agent.csh /usr/local/share/jldg/jldg-agent-core.sh
python3 -m json.tool /etc/oidc-agent/jldg-client.json >/dev/null
python3 -m json.tool /etc/oidc-agent/issuer.config.d/jldg >/dev/null
```

期待結果：配置ファイルは root 所有で一般利用者に書き込み権限がなく、スクリプトは実行可能である。構文・JSON の確認は終了状態 0 になる。

`/etc/oidc-agent/config` は行全体の `#` コメントを許すため、そのまま `json.tool` に渡さない。次の確認ではコメント行を除去して解析し、今回の3設定とクライアント情報を確認する。

```bash
python3 - <<'PY'
import json
from pathlib import Path

config_path = Path('/etc/oidc-agent/config')
text = ''.join(line for line in config_path.read_text().splitlines(True)
               if not line.lstrip().startswith('#'))
config = json.loads(text)
for key in ('auto-reauthenticate', 'autoload', 'auto-gen'):
    if config['oidc-agent'].get(key) is not False:
        raise SystemExit(f'設定を確認してください: oidc-agent.{key}')
client = json.loads(Path('/etc/oidc-agent/jldg-client.json').read_text())
issuer = json.loads(Path('/etc/oidc-agent/issuer.config.d/jldg').read_text())
if not client.get('client_id') or 'REPLACE_WITH_' in client['client_id']:
    raise SystemExit('登録済みの client_id を設定してください')
if not client.get('issuer_url') or client['issuer_url'] != issuer.get('issuer'):
    raise SystemExit('issuer が一致していません')
if issuer.get('pw-store') is not True:
    raise SystemExit('issuer の pw-store を true にしてください')
print('システム側の3設定、client_id、issuer、pw-store: OK')
PY
```

これはユーザー設定とのマージ結果や OP の登録内容までは検査しない。scope・redirect URI・audience は OP の実設定と照合し、ユーザー設定は前節の手順で確認する。

## 5. 利用者としての動作確認

検証用の一般利用者で実行ホストへログインする。別 PC から操作する場合は SSH を使う。以下は 5.7 を除き Bash で実行する。管理者のシェルや root の環境を引き継がず、利用者が普段使うログイン環境で確認する。トークンを表示するコマンドには `>/dev/null` を付ける。

### 5.1 初回登録

`oidc-gen --accounts` で `jldg` が未登録であることを確認する。既存アカウントを削除して初回を再現するのではなく、未登録の検証用利用者を使う。

```bash
oidc-gen --accounts
eval "$(/usr/local/share/jldg/jldg-agent.sh start)"
printf 'start status=%s\n' "$?"
```

初回は暗号化パスワードの設定と確認、ブラウザ認証が必要である。**ブラウザを開く場所にかかわらず、JLDG の証明書がインストールされたブラウザを使う。** 認証 URL が表示されたら、認証待ちの元の端末はそのままにする。

実行ホストと同じマシンでブラウザを開く場合は、認証 URL を直接開く。SSH 転送や SOCKS proxy は不要である。

別 PC のブラウザを使う場合は、PC の別端末で SSH 接続を作る。例としてコールバック用ポート `4243` が選択された場合、普段使う SSH コマンドの接続先より前にオプションを追加する。

```bash
ssh -N -o ExitOnForwardFailure=yes -L 4243:localhost:4243 -D 1080 YOUR_SSH_HOST_ALIAS
```

`YOUR_SSH_HOST_ALIAS` は oidc-agent を実行しているホストへの実際の接続先に置き換える。普段必要なユーザー名、踏み台、鍵等のオプションも使う。`-L` のポートは表示に合わせる。`-L` は localhost コールバック用、`-D 1080` はブラウザから OP へ実行ホスト経由で接続する SOCKS proxy 用である。

その PC のブラウザで SOCKS5 proxy のホストを `localhost`、ポートを `1080` に設定する。SSH 接続を維持したまま認証 URL を開く。認証完了後、元の端末の処理が完了したらブラウザの proxy 設定を元に戻し、転送端末を Ctrl-C で終了する。[転送手順の詳細](README.md#ブラウザ認証時の転送)

確認した oidc-agent 5.3.6 は約40秒（20回×2秒）の自動照会後、`Please press Enter to try it again.` を表示して入力を待つ。照会回数・間隔はプログラム内の定数であり、通常の設定・オプションでは変更できない。この表示ではまだ終了していない。ブラウザ認証を完了してから元の端末で Enter を押す。認証未完了で Enter を押す、または標準入力が EOF になると、最後の1回の照会に失敗して終了する。

helper は標準入力が端末でない場合、利用可能な制御端末 `/dev/tty` に接続し直す。これにより `eval`・バッククォート経由でも Enter 待ちを維持する。端末のないバッチ実行でブラウザ認証を行うことは想定しない。OP 自身の認証セッションの期限は別であり、失効した場合はやり直す。

`accepted` は生成要求の受付を示し、認証・保存の成功を示さない。`No account exists ...`、`Generating account configuration ...`、`accepted` が失敗後に見えることがあるのは、oidc-gen の標準出力がパイプでバッファリングされ、終了時に遅れて表示されるためである。現行 helper は、この3行を標準出力から完全一致で除外して表示しない。標準出力と標準エラーの合流後に、state 再照会の見出しと `oidc-gen --state=...` の行だけを逐次処理で除外する。認証 URL・失敗理由・改行のない入力案内は即時表示する。他の標準出力メッセージも表示する。[自動照会と Enter 待ちの実装](https://github.com/indigo-dc/oidc-agent/blob/v5.3.6/src/oidc-gen/gen_handler.c#L392)・[受付状態の表示](https://github.com/indigo-dc/oidc-agent/blob/v5.3.6/src/oidc-gen/parse_ipc.c#L76)

期待結果：パスワード入力案内と認証 URL が入力前に表示され、転送案内のポートが URL の `redirect_uri` と一致する。登録後に `JLDG authentication is ready for Gfarm.` と表示され、`start status=0` になる。

### 5.2 agent・環境変数・トークン取得

初回登録と同じシェルで実行する。

```bash
printf 'JWT_USER_PATH=%s\n' "${JWT_USER_PATH-}"
test -S "$OIDC_SOCK"
printf 'socket status=%s\n' "$?"
kill -0 "$OIDCD_PID"
printf 'process status=%s\n' "$?"
oidc-agent --status
oidc-add --loaded
oidc-token --time=60 jldg >/dev/null
printf 'token status=%s\n' "$?"
```

期待結果：`JWT_USER_PATH` は `!oidc-token --time=60 jldg`。socket・process・token はすべて終了状態 0、読み込み済みアカウントに `jldg` がある。`--time=60` は残存有効時間の要求であり、トークンの寿命を60秒に設定するものではない。[oidc-token の仕様](https://indigo-dc.github.io/oidc-agent/usage/oidc-token/options/)

`oidc-agent --status` では、実際に稼働する agent のバージョンが 5 系で、`Autoload` と `Auto Re-authenticate` が `false`、`Webserver` が `true`、`Confirm` が `false` であることを確認する。項目の表記は導入版に従う。`auto-gen` は設定ファイルも確認する。既定の保持時間は無期限である。[agent の状態表示](https://indigo-dc.github.io/oidc-agent/usage/oidc-agent/options/#-status)

暗号化アカウントファイルの保存先は、通常 `~/.config/oidc-agent` または `~/.oidc-agent` で、`OIDC_CONFIG_DIR` を指定している場合はそのディレクトリとなる。`jldg` ファイルが利用者本人の所有で、他の利用者に読み書きを許さないことも確認する。ディレクトリは `0700`、アカウントファイルは `0600` を基本とし、内容を表示して確認する必要はない。[アカウント保存先の公式説明](https://indigo-dc.github.io/oidc-agent/configuration/directory/)

### 5.3 Gfarm 接続

管理者が用意した、読み取り可能な検証用ディレクトリと小さなファイルを指定する。

```bash
JLDG_TEST_DIR='gfarm:///REPLACE_WITH_TEST_DIRECTORY'
JLDG_TEST_FILE='gfarm:///REPLACE_WITH_TEST_FILE'
gfls "$JLDG_TEST_DIR"
printf 'gfls status=%s\n' "$?"
gfexport "$JLDG_TEST_FILE" >/dev/null
printf 'gfexport status=%s\n' "$?"
```

期待結果：両方が終了状態 0。ディレクトリ参照だけでなくファイルのデータ取得まで成功する。

**成功の判定には、XOAUTH2 を利用したことの確認も必要である。** 検証用のクライアント設定で他の認証方式へのフォールバックを無効にするか、サーバー側ログ等で実際に選ばれた認証方式と SASL メカニズムを確認する。`gfls` の成功だけでは、sharedsecret や GSI など別方式で成功した可能性を除外できない。既存の `sasl_password`、`GFARM_SASL_PASSWORD` や別のトークン取得設定が使われていないことも確認する。

### 5.4 繰り返し開始と refresh token の利用

```bash
eval "$(/usr/local/share/jldg/jldg-agent.sh start)"
printf 'repeat start status=%s\n' "$?"
oidc-token --force-new jldg >/dev/null
printf 'refresh status=%s\n' "$?"
```

期待結果：両方が終了状態 0。正常な読み込み済みアカウントでは通常、パスワード入力やブラウザ認証を再度要求しない。`--force-new` はキャッシュ済みアクセストークンが有効でも更新を試すため、更新経路の確認になる。

### 5.5 停止と保存済みアカウントの再読み込み

同じシェルで実行する。検証用利用者の agent を共有する別端末がある場合は、先に利用への影響を確認する。

```bash
eval "$(/usr/local/share/jldg/jldg-agent.sh stop)"
printf 'stop status=%s\n' "$?"
for jldg_name in JWT_USER_PATH OIDC_SOCK OIDCD_PID OIDCD_PID_FILE; do
    if printenv "$jldg_name" >/dev/null; then
        printf 'FAIL: %s remains set\n' "$jldg_name"
    else
        printf 'OK: %s is unset\n' "$jldg_name"
    fi
done
oidc-gen --accounts
```

期待結果：停止が終了状態 0、4変数は解除され、保存済みアカウントには `jldg` が残る。停止は発行済みトークンの取り消しではないので、Gfarm 接続の成否だけで停止を判定しない。

```bash
eval "$(/usr/local/share/jldg/jldg-agent.sh start)"
printf 'reload status=%s\n' "$?"
oidc-token --force-new jldg >/dev/null
printf 'refresh after reload status=%s\n' "$?"
```

暗号化パスワードを入力し、正常ならブラウザ認証なしで再読み込みできることを確認する。5.3 の Gfarm 接続も再確認する。OP が refresh token をローテーションする構成では、更新後の停止・再読み込みも成功することをもって保存の動作を確認する。OP がローテーションしない場合、ローテーション時の保存動作はこの確認だけでは検証できない。

### 5.6 別端末とホスト再起動後

ログアウトして同じ利用者・同じホストへログインし直した場合も、`start` を `eval` して環境変数を復元する。確認した公式5.3.6の service は再利用時に `OIDCD_PID` を空または継承値で出力するため、helper は `OIDCD_PID_FILE` の内容を読み取って正しい PID を設定する。環境変数をファイルへ保存して source する必要はない。


同じ利用者・同じ実行ホストの別端末から `start` を実行し、5.2 と 5.3 を確認する。通常は起動済み agent を共有し、ブラウザ認証なしで使用できる。`TMPDIR`、`OIDC_CONFIG_DIR` 等を独自に指定する環境では、端末間で同じ agent・アカウント設定を参照することも確認する。

実行ホストの再起動が必要な導入では、計画した保守時間に再起動してから同じ利用者でログインし、5.5 の再読み込みと 5.3 を行う。helper 自体には再起動後の自動復旧機能はない。

### 5.7 tcsh

tcsh 利用者へ配布する場合は、tcsh にログインして次を確認する。Bash 用の入口を `source` して使わない。

```csh
eval `/usr/local/share/jldg/jldg-agent.csh start`
echo "start status=$status"
printenv JWT_USER_PATH
oidc-token --time=60 jldg >/dev/null
echo "token status=$status"
```

期待結果：開始とトークン取得の終了状態が 0、`JWT_USER_PATH` が Bash と同じ値になる。この tcsh から検証用 Gfarm パスへのアクセスも確認する。

```csh
eval `/usr/local/share/jldg/jldg-agent.csh stop`
echo "stop status=$status"
printenv JWT_USER_PATH OIDC_SOCK OIDCD_PID OIDCD_PID_FILE
```

期待結果：停止の終了状態が 0、最後の `printenv` は出力なし・非0で、変数が残っていない。停止後、再び `start` できることも確認する。

## 6. 再認証と異常時の確認

失効の確認には専用の検証用 OP アカウントを使う。`stop`、アクセストークンの有効期限切れ、ブラウザからのログアウトだけでは refresh token の失効を保証しない。OP 管理機能等で、対象クライアントの検証用 refresh token が失効したことを確認する。

### 6.1 読み込み済みアカウントの失効

1. `start` と 5.2 を成功させた状態で、OP 側で検証用 refresh token を失効させる。
2. `start` を再実行する。
3. `JLDG reauthentication required.` の案内と認証 URL が表示されることを確認し、5.1 のブラウザを開く場所に応じた手順で認証する。別 PC の場合は SSH 転送と SOCKS5 proxy を使う。
4. 開始の終了状態 0、5.2 のトークン取得、5.3 の Gfarm 接続を確認する。

このケースでは、読み込み後の `oidc-token --force-new` の失敗から再認証へ進むことを確認する。

### 6.2 未読み込みの保存済みアカウントの失効

1. 正常なアカウントを用意し、`stop` を実行する。
2. OP 側で、そのアカウントの検証用 refresh token を失効させる。
3. `start` を実行し、暗号化パスワードを入力する。
4. `oidc-add` の失効エラーで終了せず、再認証の案内へ進むことを確認する。
5. 5.1 のブラウザを開く場所に応じた手順で認証を完了し、終了状態 0、トークン取得、Gfarm 接続を確認する。

このケースは、保存済みアカウントの読み込み時の失敗も再認証判定へ渡す修正の確認になる。

### 6.3 再認証すべきでないエラー

検証環境で、OP への通信障害、または暗号化パスワードの読み込み失敗を再現する。通信制限を使う場合は対象を検証環境に限定し、確認後に元へ戻す。

期待結果：`start` の終了状態が非0で、`JWT_USER_PATH` が解除され、ブラウザ再認証を開始しない。パスワード誤入力時は、oidc-agent が再入力を求める場合があるため、入力をキャンセルする等により読み込み失敗が確定した時点で判定する。通信や入力の問題を解消した後、`start` を再実行して復旧できることを確認する。

## 7. 障害時の切り分け

| 症状 | 主な確認箇所 |
|---|---|
| `Required command not found` | 利用者の `PATH`、パッケージと依存関係。管理者と利用者の環境差 |
| クライアント設定を読めない | 配置先、権限、`JLDG_CLIENT_CONFIG` |
| 認証 URL が出ない・登録に失敗 | 未置換の client ID、issuer・scope、OP 到達性、ローカル待受ポートの空き |
| ブラウザから OP へ接続できない | JLDG の証明書、実行ホストからの OP 到達性。別 PC では SOCKS5 proxy の localhost:1080、SSH の -D 1080、SOCKS5 経由のホスト名解決 |
| ブラウザ認証後に処理が進まない | OP に登録した URI、選択ポート。別 PC では SSH の -L、localhost の proxy 除外、接続先ホストの取り違え |
| 転送案内が出ない | URL の `redirect_uri` 表記。本 helper はパーセントエンコードされた `http://localhost:ポート` のみ対応 |
| Gfarm 実行中に GUI の入力要求が出る | 起動済み agent の設定、ユーザー設定・service 起動オプションによる上書き、他ツールによる起動 |
| トークン取得は成功し Gfarm は失敗 | TLS・CA、XOAUTH2、issuer・audience・scope、ユーザー対応、利用権限 |
| Gfarm は成功するが helper を使っていないように見える | 他認証方式へのフォールバック、`sasl_password`、`GFARM_SASL_PASSWORD`、別の環境変数設定 |
| 他端末で停止した後に接続できない | agent の共有。他端末に残った環境変数は解除されないので、その端末で `start` を再実行 |
| 停止・再起動後に更新に失敗 | `pw-store`、OP のローテーション方針、ユーザー側 issuer 設定、ホームを共有する別ホストからの利用 |

調査記録にはコマンドのバージョン、実行ホスト、シェル、実施ケース、終了状態、必要なエラー文を残す。トークン本体、暗号化パスワード、復号したアカウント設定は記録しない。通常確認に `oidc-gen --print` やデバッグログは不要である。

## 8. 更新時の再確認と導入完了の判定

oidc-agent を更新したら、特に再認証を促すエラー文と認証 URL の表記を再確認する。helper はこれらを解析する。排他処理は実装していないため、同じ利用者による同時初回登録・同時新規起動は検証・運用の対象外とする。

ホームを複数ホストで共有する場合は、暗号化アカウントファイルと refresh token をどの範囲で共有するか、OP のローテーション方針と合わせて決定する。ホストごとの agent は別プロセスであり、共有ファイルへの競合を helper は制御しない。

導入記録には、OS、oidc-agent/Gfarm の版、配置先、検証用利用者、対象 OP・クライアント、以下の結果を残す。

- [ ] ファイルの配置・所有者・権限・構文・JSON と OP の登録値を確認した。
- [ ] 3つの無効化設定、ユーザー設定、実際の稼働 agent の設定を確認した。
- [ ] JLDG の証明書がインストールされたブラウザで初回登録・認証に成功した。別 PC の場合は SSH ローカル転送・SOCKS5 proxy も確認した。
- [ ] トークン取得、繰り返し開始、停止・再読み込みに成功した。
- [ ] XOAUTH2 による Gfarm のメタデータ参照・ファイル読み取りに成功した。
- [ ] 読み込み済み・未読み込みの両方で、失効から再認証に成功した。
- [ ] 通信・パスワードエラーでは再認証せず失敗を返し、原因解消後に復旧した。
- [ ] 対象のシェル、別端末、必要ならホスト再起動後の確認を行った。

実施できなかった項目は未確認として記録し、条件と残作業を明記する。導入完了時には [README.md](README.md) のうち利用者のシェルに合う操作方法とブラウザの手順を案内し、別 PC を使う場合は普段使う SSH 接続先も伝える。
