# JLDG oidc-agent helper

JLDG の OIDC 認証を準備し、Gfarm が必要時にアクセストークンを取得できるようにする。利用者は `start` で開始し、`stop` で停止する。状態は `status` で確認できる。

**管理者によるインストール・設定・動作確認は [簡易版](ADMIN_QUICKSTART.md) を参照する。設定の詳細や障害対応は [管理者マニュアル](ADMIN_GUIDE.md) に記載する。** この README は、導入済みの環境で利用者が操作する手順を示す。以下の配置先は `/usr/local/share/jldg` とする。

## 開始と停止

利用者のシェルに合う一方の手順を使う。アカウント登録や agent の起動は、Gfarm を利用する本人として行う。

Bash:

```bash
eval "$(/usr/local/share/jldg/jldg-agent.sh start)"
eval "$(/usr/local/share/jldg/jldg-agent.sh stop)"
```

tcsh:

```csh
eval `/usr/local/share/jldg/jldg-agent.csh start`
eval `/usr/local/share/jldg/jldg-agent.csh stop`
```

通常は `start` だけを実行し、利用を終えて agent を停止するときに `stop` を実行する。3つのスクリプトはすべて Bash で動き、`.csh` の入口は tcsh 用の環境設定を出力する。ログインシェルを Bash に変更する必要はない。

`start` と `stop` の出力を `eval` することで、現在のシェルと以後の子プロセスに環境変数を反映する。これらを `eval` なしで実行したり `source` で読み込んだりしても、上記の操作の代わりにならない。

`start` は次の処理を行う。

1. agent を起動するか、起動済みの agent に接続する。
2. 未登録ならブラウザ認証で `jldg` アカウントを作成し、登録済みなら読み込む。
3. refresh token による更新を確認する。読み込み・更新の際に再認証が必要と案内された場合だけ、ブラウザ認証へ進む。
4. 成功した場合だけ、agent への接続情報と `JWT_USER_PATH` を設定する。

初回は暗号化パスワードの設定と確認、保存済みアカウントの読み込み時はそのパスワードの入力が必要になる。正常な読み込み済みアカウントでは通常、再入力は不要である。issuer・client ID・scope・redirect URI は管理者が設定する。

`JWT_USER_PATH` の値は次のとおりで、Gfarm が認証時にコマンドを実行してトークンを取得する。

```text
!oidc-token --time=60 jldg
```

`--time=60` は残存有効時間を60秒以上要求する指定であり、トークンの寿命を60秒にするものではない。

`stop` は接続中の agent を停止し、現在のシェルの環境変数を解除する。`OIDC_SOCK` が未設定・空の場合は `Not connected to a JLDG agent.`、接続先が応答しない場合は `JLDG agent is not running or not connected.` と表示し、停止操作は行わず環境変数だけ解除する。未接続のシェルから稼働中の agent を停止したい場合は、先に `start` で再接続する。`JLDG agent stopped.` は接続確認と停止処理が成功した場合だけ表示する。暗号化アカウントファイルは残る。発行済みトークンを取り消す操作ではない。

## ログインし直した後

ログアウトするとシェルの環境変数は失われる。同じ利用者・同じホストでログインし直したら、上記の `start` を再び `eval` する。既存 agent があれば再利用し、接続情報と `JWT_USER_PATH` を設定し直す。service が PID を空で返す場合も、返された PID ファイルから読み取る。agent 自体が停止していれば新しく起動し、保存済みアカウントを読み込む。

## 状態確認

状態確認は **`eval` を付けずに**実行する。

Bash:

```bash
/usr/local/share/jldg/jldg-agent.sh status
```

tcsh:

```csh
/usr/local/share/jldg/jldg-agent.csh status
```

agent への接続可否、`jldg` の読み込み状態、現在のシェルの `JWT_USER_PATH` の設定状態と、agent のバージョン・起動設定を表示する。`OIDC_SOCK` があればその接続先を使い、未設定なら oidc-agent の既定の接続先を調べる。接続できない場合は `JLDG agent is not running or not connected.` の1行だけを表示し、設定情報や内部エラーは表示しない。未起動と接続先の問題は区別しない。

`status` は起動・停止・アカウント読み込み・認証・トークン更新・環境変数の変更を行わない。`JLDG account: loaded` はトークンの有効性を保証しないので、認証を準備・復旧するときは `start` を使う。状態取得に成功すれば終了状態は 0、接続や状態取得に失敗すれば非0となる。0 でも `jldg` が未読み込み、または現在のシェルが未設定の場合がある。

## ブラウザ認証時の転送

初回登録と再認証では、認証 URL とブラウザを開く場所に応じた手順を表示する。**どちらの場合も、JLDG の証明書がインストールされたブラウザを使う。** 認証待ちの元の端末はそのままにする。

**oidc-agent と同じマシンでブラウザを開く場合**

そのマシンのブラウザで認証 URL を直接開く。この手順のための SSH 転送や SOCKS proxy は不要である。

**oidc-agent とは別の PC でブラウザを開く場合**

1. PC の別端末で、普段の SSH コマンドの接続先より前に、表示された転送オプションを追加する。接続先は oidc-agent を実行しているホストとし、普段のホスト別名・ユーザー名・踏み台等の指定を使う。
2. JLDG の証明書がインストールされたブラウザで、SOCKS5 proxy のホストを `localhost`、ポートを `1080` に設定する。
3. SSH 接続を維持したまま、そのブラウザで認証 URL を開く。OP への接続は SOCKS proxy を通って実行ホストを経由する。
4. 認証が終わり元の端末の処理が完了したら、ブラウザの proxy 設定を元に戻し、転送用端末を Ctrl-C で終了する。

例えばコールバック用ポートが `4243` の場合、PC 側で次を実行する。

```bash
ssh -N -o ExitOnForwardFailure=yes -L 4243:localhost:4243 -D 1080 YOUR_SSH_HOST_ALIAS
```

`YOUR_SSH_HOST_ALIAS` は実際の接続先に置き換え、`-L` のポート番号は表示に合わせる。`-L` は認証後の localhost コールバックを届け、`-D 1080` は OP への接続に使う SOCKS proxy を PC 上で提供する。`-N` のため、この接続ではシェルのプロンプトは出ない。PC 側ではコールバック用ポートと `1080` が使用可能である必要がある。

スクリプトは SSH 接続の作成やブラウザの設定を自動では行わない。実行ホストから OP への HTTPS 接続が必要である。

自動照会が止まって `Please press Enter to try it again.` と表示された場合は、**ブラウザ認証を完了してから、元の端末で Enter を押す。** SSH やブラウザの準備中には Enter を押さず、そのまま待たせてよい。Enter は最後の1回の照会を行う操作であり、自動照会をもう20回繰り返す操作ではない。OP 側で認証セッションが失効した場合は `start` からやり直す。

## 失敗時と複数端末での利用

- 遅れて表示されると誤解を招くため、oidc-gen の `No account exists ...`、`Generating account configuration ...`、`accepted` の3行、および失敗時の state 再照会コマンドの案内は helper が表示しない。認証 URL・入力案内・失敗理由は表示する。成功は `JLDG authentication is ready for Gfarm.` と開始の終了状態0で確認する。
- クライアント JSON は管理者が正しく設定済みであることを前提とする。helper はファイルを読めるかだけ確認し、構文・必須項目の事前検査は行わない。
- `Enter decryption password for /etc/oidc-agent/jldg-client.json:` と表示された場合は、管理者が JSON の構文や文字コードを確認する。oidc-agent は JSON オブジェクトとして読めないファイルを暗号化ファイルとして扱う。
- パスワード入力中の中断に備え、`start` は開始時の端末設定を保存し、終了時に復元する。旧版の中断後などで入力文字が見えない場合は、`stty echo` と入力して Enter を押す。入力文字が見えなくても実行できる。

- 通信障害や暗号化パスワードの誤りなどでは、ブラウザ再認証を始めずに失敗する。原因を解消して `start` を再実行する。
- 開始失敗・中断時は `JWT_USER_PATH` を解除して非0の終了状態を返す。認証失敗・ポーリング失敗・Ctrl-C などのいずれでも、今回の処理で新規起動した agent を停止する。既に起動していた共有 agent を再利用した場合は停止しない。停止に失敗した場合は手動停止の案内を表示する。
- 停止失敗時も `JWT_USER_PATH` を解除して失敗を返すが、既存の接続用環境変数は残す。引数の誤りでは環境を変更しない。
- 未読み込みのアカウントや、失効した refresh token は、`start` の再実行で読み込み・再認証する。Gfarm の実行中に agent が自動で登録・読み込み・再認証を始める設定にはしていない。
- 同じ利用者・同じホストの agent は複数端末で共有する。別端末からの `stop` も共有 agent 全体に影響する。他端末の環境変数は解除されないので、その端末で再び `start` を実行する。
- 同じ利用者による同時初回登録・同時新規起動は保証しない。ホスト再起動後は `start` を再実行する。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `jldg-agent.sh` | Bash 用の入口 |
| `jldg-agent.csh` | tcsh 用の入口 |
| `jldg-agent-core.sh` | agent 管理、状態確認、初回登録、再認証、転送案内、環境設定出力 |
| `jldg-client.json` | 管理者が設定する public client 情報 |
| `issuer.config.d/jldg` | JLDG 用の暗号化パスワード保持設定 |
| [ADMIN_QUICKSTART.md](ADMIN_QUICKSTART.md) | 管理者向けの導入・基本動作確認の簡易手順 |
| [ADMIN_GUIDE.md](ADMIN_GUIDE.md) | 管理者向けの導入、動作確認、障害切り分け、更新時の注意 |
| [HANDOFF.md](HANDOFF.md) | 別の AI 向けの変更経緯、決定事項、検証結果、未対応事項 |
