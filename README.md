# JLDG OIDC 認証補助

JLDG の Gfarm をトークン認証（OpenID Connect）で利用するための、oidc-agent 用の補助スクリプトと設定ファイル一式である。

- 利用者は、手元の PC のブラウザと JLDG ユーザ証明書で、JLDG の OpenID Provider（OP、`https://idp.jldg.org`）に本人確認を行う。
- 実行ホスト（Gfarm クライアントを実行する JLDG クライアント）では、利用者ごとの oidc-agent（agent）が、リフレッシュトークン（RT）でアクセストークンを更新する。
- Gfarm は、`JWT_USER_PATH` に設定された `jldg-auth --token` でアクセストークンを取得する。
- agent の起動・接続・停止は、利用者が oidc-agent 標準の `oidc-keychain` で行う。jldg-auth は agent を起動・停止しない。

## 文書一覧

| 読者 | 文書 | 内容 |
| --- | --- | --- |
| 利用者 | [USER_QUICKSTART.md](USER_QUICKSTART.md) | 初回登録から Gfarm の利用までの最短手順 |
| 利用者 | [USER_GUIDE.md](USER_GUIDE.md) | 仕組み、再認証、困ったとき、停止、自動準備を含む手順書 |
| 管理者 | [ADMIN_QUICKSTART.md](ADMIN_QUICKSTART.md) | 配置・設定・動作確認の最短手順 |
| 管理者 | [ADMIN_GUIDE.md](ADMIN_GUIDE.md) | 設定の理由、詳しい確認項目、障害時の切り分け |
| 保守担当者 | 本書 | ファイル構成と jldg-auth の動作仕様 |

利用者向けの2文書は、ほかの文書を読まなくても使えるように書いている。

## ファイル構成

| ファイル | 配置先の例 | 役割 |
| --- | --- | --- |
| `jldg-auth` | `/usr/local/jldg/` | 利用準備、ブラウザ認証、Gfarm 向けのトークン取得 |
| `jldg-env.sh` / `jldg-env.csh` | `/usr/local/jldg/` | Bash / tcsh 用の環境設定。PATH と `JWT_USER_PATH` を設定する |
| `jldg-auth.conf` | `/etc/oidc-agent/` | 初回登録・再認証で oidc-gen に渡すオプション（`JLDG_GEN_OPTIONS`）と、クライアント JSON の既定のパス |
| `jldg-client.json` | `/etc/oidc-agent/` | OP に登録した public client の情報 |
| `issuer.config.d/jldg` | `/etc/oidc-agent/issuer.config.d/` | 更新された RT を保存するためのパスワード保持（`pw-store`）設定 |

必要なコマンドは、引数なしと `--no-browser` では Bash 4.2 以降、`stty`、oidc-agent 5 系一式、`--token` では Bash と `oidc-token` である。配置と設定の手順は [ADMIN_GUIDE.md](ADMIN_GUIDE.md) を参照する。

## 環境設定スクリプト

```bash
source /usr/local/jldg/jldg-env.sh    # Bash
```

```csh
source /usr/local/jldg/jldg-env.csh   # tcsh
```

配置先を `PATH` の先頭に追加し、`JWT_USER_PATH` を `!jldg-auth --token` に設定する。繰り返し source しても PATH は重複しない。agent の操作、認証、トークン取得は行わず、`OIDC_SOCK` 等も変更しない。配置先が `/usr/local/jldg` でない場合は、source の前に `JLDG_HELPER_DIR` をその絶対パスに設定する。

## agent との関係

利用者は、ログインのたびに次で agent に接続する。agent が動いていなければ起動される。

```bash
eval "$(oidc-keychain)"        # Bash
```

```csh
eval `bash -c 'eval "$(oidc-keychain)" >/dev/null; printf "setenv OIDC_SOCK %q;\n" "$OIDC_SOCK"'`   # tcsh
```

oidc-keychain 5.3.6 の出力は Bash 形式なので、tcsh では一度 Bash で評価して `setenv` に変換する。内側の `>/dev/null` は、PID の表示が変換結果に混ざるのを防ぐ。停止は Bash では `eval "$(oidc-keychain --kill)"`、tcsh では `oidc-keychain --kill` の成功後に `unsetenv OIDC_SOCK OIDCD_PID OIDCD_PID_FILE` を実行する。

`oidc-keychain --accounts jldg` は使わない。5.3.6 は `oidc-prompt` が見つかると内部の oidc-add に GUI 入力を指定するため、接続（oidc-keychain）と読み込み（jldg-auth）を分けている（[公式実装](https://github.com/indigo-dc/oidc-agent/blob/v5.3.6/src/oidc-keychain/oidc-keychain)）。

agent 自身の自動読み込み・自動生成・自動再認証は、管理者設定で無効にする（[ADMIN_GUIDE.md 3.3](ADMIN_GUIDE.md#33-etcoidc-agentconfig)）。そのため、アカウントの読み込みと再認証は、対話端末で実行する jldg-auth だけが行う。

## jldg-auth の動作

### モード

| 実行方法 | 呼び出し元 | 端末 | 動作 |
| --- | --- | --- | --- |
| `jldg-auth` | 利用者 | 必須 | 利用準備。必要な場合だけ初回登録・ブラウザ再認証を行う |
| `jldg-auth --no-browser` | 利用者、シェル起動設定 | 必須 | 利用準備のうち、読み込みとトークン取得の確認だけを行う |
| `jldg-auth --token` | Gfarm（`JWT_USER_PATH`） | 不要 | トークンを標準出力に返す |
| `jldg-auth --help` | 利用者 | 不要 | 使い方を標準出力に表示する |

標準出力に書くのは `--token` のトークンと `--help` だけで、メッセージはすべて標準エラーに出す。source した場合は、何もせずにエラーを表示して終了する。

### 利用準備（引数なし、`--no-browser`）

1. 標準入力が端末でなければ終了する。必要なコマンドを確認し、端末設定を保存する。
2. `oidc-agent --status` で agent に接続できなければ終了する。
3. `oidc-gen --accounts` でアカウント `jldg` が保存されているかを確認する。一覧を取得できなければ終了する。
4. 未登録の場合：
   - `--no-browser` では、`jldg-auth` の実行を案内して終了状態1で終了する。
   - 引数なしでは、`jldg-auth.conf` とクライアント JSON を読み、`oidc-gen --file=<JSON> jldg` で初回登録する（ブラウザ認証）。
5. 登録済みの場合：`oidc-add jldg` で読み込み、`oidc-token --time=60 jldg` でトークンを取得できることを確認する。未読み込みのアカウントの読み込みでは、oidc-add が OP のメタデータ取得と RT による更新を行う。読み込み済みなら oidc-add は更新を省略し、トークン取得はキャッシュを再利用する。成功すれば完了。
6. 手順5で、OP が RT を無効と明示した場合（次節）だけ、`jldg-auth.conf` を読んで `oidc-gen --reauthenticate jldg` で再認証する。`--no-browser` では再認証せず、`jldg-auth` の実行を案内して、元の終了状態で終了する。それ以外の失敗（通信障害、パスワード入力の失敗など）では再認証しない。
7. 初回登録・再認証の後は、もう一度 `oidc-token --time=60 jldg` で取得を確認する。1回の実行の中で再認証を繰り返すことはない。
8. 取得を確認できた場合だけ `JLDG is ready.` を表示する。トークン本体は表示しない。

`jldg-auth.conf` とクライアント JSON は、ブラウザ認証に進む場合だけ読む（再認証ではクライアント JSON も不要）。クライアント JSON の構文は検査しない。`jldg-auth.conf` が `JLDG_GEN_OPTIONS` を空でない配列として定義していなければ、ブラウザ認証を始めずに終了する。

`JLDG is ready.` は、その時点でアクセストークンを取得できたことを示す。毎回の強制更新は行わないため、RT の現在・将来の有効性までは保証しない。

同じアカウントの初回登録・ブラウザ再認証を、複数の端末から同時に実行することは想定していない（排他制御はしない）。競合すると、認証処理や設定の保存が失敗し、やり直しが必要になる場合がある。

### Gfarm 向けのトークン取得（`--token`）

`oidc-token --time=60 jldg` を一度だけ呼び、成功時だけトークンを標準出力へ返す。失敗時は、部分的な標準出力を捨て、元の終了状態を保って非0で終了する。標準入力は消費しない。管理者設定を読まず、読み込み・初回登録・ブラウザ再認証・自動リトライは行わない。

`--time=60` は、アクセストークンの残り有効時間として60秒以上を求める指定である。条件を満たすキャッシュがあれば OP に問い合わせずに返し、なければ agent が RT で更新する。JLDG の RT は発行から1か月有効で、更新のたびに、そこから1か月有効な新しい RT に置き換わる。キャッシュを返すだけでは RT は更新されない。RT による更新を実際に試す方法は [ADMIN_GUIDE.md 5.4](ADMIN_GUIDE.md#54-保存済みアカウントの読み込みと更新確認) を参照する。

### エラーの判定と表示

oidc-agent のコマンドの標準エラーは、1文字ずつ端末へ転送する。そのため、改行のないパスワード入力の案内もすぐに表示される。OP のエラー本文はそのまま残す。

- **RT の拒否：** `Error:` で始まる行が、`invalid_grant` または `invalid_token` と `refresh token` を含む場合、または `no refresh token` を含む場合に、RT が無効と判定する（大文字・小文字は区別しない）。失敗一般や、`--reauthenticate` という語を含むだけの診断を、期限切れとは判定しない。
- **標準の再認証案内の置き換え：** RT の拒否時に oidc-agent が表示する `oidc-gen jldg --reauthenticate` の案内を直接実行すると、SSH 転送・SOCKS5 プロキシの案内が出ない。そのため、既知の案内の行は表示せず、jldg-auth の案内に置き換える。
- **IPC の切断：** `Error:` で始まる行が `the other party disconnected` を含む場合は、agent との通信の切断と判定する。jldg-auth は agent への接続を再確認して案内を分ける。OP の停止・パスワード誤り・失効とは断定せず、再認証・agent の再起動・自動リトライは行わない。
- **oidc-gen の状態検索の案内：** jldg-auth は `oidc-gen --state=...` による手動の状態検索に対応しないため、その案内は表示せず、jldg-auth の再実行を案内する。
- **転送の案内：** oidc-gen が出力した認証 URL の `redirect_uri` から `http://localhost:ポート` を読み取り、SSH 転送とブラウザ設定の案内を表示する。パーセントエンコードされた localhost の URI だけに対応する。

終了状態0のコマンドがエラーの診断を出した場合は、成功とみなさない。

### 主なメッセージ

| メッセージ | 意味 |
| --- | --- |
| `JLDG is ready.` | 利用準備が完了した |
| `JLDG account registration completed.` / `JLDG reauthentication completed.` | 初回登録・再認証が完了した（続けて取得を確認する） |
| `The refresh token was rejected. Starting JLDG browser reauthentication.` | RT の拒否を検出し、再認証を始める |
| `Browser authentication:` で始まる案内 | SSH 転送とブラウザ設定の案内 |
| `JLDG account is not registered. Run in a terminal: jldg-auth` | `--no-browser` で未登録だった |
| `JLDG reauthentication is required. Run in a terminal: jldg-auth` | RT の拒否を検出したが、このモードでは再認証しない |
| `JLDG account registration did not complete.` / `JLDG reauthentication did not complete.` | oidc-gen が失敗した。jldg-auth の再実行を案内する |
| `Cannot connect to oidc-agent. Run oidc-keychain to start or reconnect the agent, then retry jldg-auth.` | agent に接続できない |
| `JLDG: Communication with oidc-agent was interrupted; ...` | IPC の切断。続く行で、agent に接続できるかに応じた案内を出す |
| `JLDG operation failed. Check the original error above.` | そのほかの失敗 |
| `JLDG token retrieval failed.` | `--token` での失敗（続けて上記のいずれかの案内を出す） |
| `Cannot read administrator configuration: ...` / `Cannot read client configuration: ...` / `JLDG_GEN_OPTIONS is not set as an array in ...` | 管理者設定の不備 |
| `Run jldg-auth in an interactive terminal. ...` | 端末のない環境で利用準備を実行した |

### 端末設定と中断

利用準備では、パスワード入力の前に端末設定を保存し、成功・失敗・Ctrl-C（INT）・TERM・HUP のいずれでも元に戻す。SIGKILL は対象外である。失敗や中断の後も、agent・アカウント・環境変数はそのまま残し、停止・削除・アンロードはしない。ファイルを作る場合に備えて、umask を 077 にする。

## ブラウザ認証と転送

認証基盤への接続元は、JLDG クライアントが属するネットワークに制限されている。利用者は手元の PC から実行ホストへ、次の転送を付けて SSH 接続する（ポート4243の例）。

```bash
ssh -N -o ExitOnForwardFailure=yes -L 4243:localhost:4243 -D 1080 YOUR_SSH_HOST_ALIAS
```

`-D 1080` は、ブラウザから OP への通信（SOCKS5 プロキシ `localhost:1080`）を実行ホスト経由にする。`-L` は、localhost コールバックで返される認証コードを実行ホストの agent へ届ける。SSH の転送とブラウザの設定は、jldg-auth は行わない。

## シェル起動時の自動準備

利用者が任意でシェル起動ファイルに追加できる設定例を、[USER_GUIDE.md](USER_GUIDE.md) の8節と [ADMIN_GUIDE.md](ADMIN_GUIDE.md) の5.6節・5.7節に示している。対話端末だけで接続と `jldg-auth --no-browser` を実行し、ブラウザ認証は始めない。jldg-auth 自身はシェルの起動ファイルを編集しない。
