# JLDG OIDC 認証補助

JLDG の初回登録・ブラウザ再認証を補助し、Gfarm が必要時にトークンを取得するための環境を設定する。agent の起動・再接続・停止には標準の `oidc-keychain`、アカウントの読み込みには `oidc-add` を使う。

管理者による導入・基本確認は [簡易版](ADMIN_QUICKSTART.md)、設定の詳細と障害対応は [管理者マニュアル](ADMIN_GUIDE.md) を参照する。以下の配置先は `/usr/local/jldg` とする。

## 環境設定

Bash では次を読み込む。

```bash
source /usr/local/jldg/jldg-env.sh
```

tcsh では次を読み込む。

```csh
source /usr/local/jldg/jldg-env.csh
```

環境設定スクリプトは、helper の配置ディレクトリを `PATH` に追加し、`JWT_USER_PATH` を `!jldg-token` に設定する。繰り返し読み込んでも同じディレクトリを重複追加しない。agent の起動・接続・認証やトークン取得は行わず、`OIDC_SOCK` 等の接続用変数も変更しない。

標準以外の場所へ導入した場合は、読み込む前に `JLDG_HELPER_DIR` をその絶対パスに設定する。設定は現在のシェルと子プロセスに適用される。自動で設定したい場合は、利用者自身のシェル起動ファイルから読み込む。

`JWT_USER_PATH` はトークン取得方法の指定であり、設定済みでも認証準備完了を意味しない。失敗・中断や agent の停止後も、この設定は残る。

## agent の準備とアカウントの読み込み

利用者本人の Bash で次を実行する。初回の起動と、別端末・再ログイン後の再接続は同じコマンドで行う。

```bash
eval "$(oidc-keychain)"
oidc-agent --status
```

同じ利用者・同じホストの agent が起動済みなら再利用し、なければ新しく起動する。`eval` は接続先を現在のシェルに反映するために必要である。`oidc-agent --status` で接続と稼働設定を確認できる。tcsh の接続方法は [管理者マニュアル](ADMIN_GUIDE.md#57-tcsh) を参照する。5.3.6 の `oidc-keychain` は Bash 形式を返すため、tcsh でその出力を直接 `eval` しない。

保存済みアカウントを新しい agent に読み込む場合は、同じシェルで次を実行する。

```bash
oidc-add jldg
```

必要に応じて暗号化パスワードを端末で入力する。正常な読み込み済みアカウントでは通常、再入力は不要である。管理者が [導入手順](ADMIN_QUICKSTART.md#3-設定する管理者) の設定を反映済みなら、CLI 入力とパスワードのメモリ保持は既定となり、`--pw-prompt=cli` と `--pw-store` は省略できる。未登録なら、先に「初回登録と再認証」節の `jldg-auth` を実行する。読み込み一覧は `oidc-add --loaded` で確認する。

本手順では `oidc-keychain --accounts jldg` を使わず、接続後に `oidc-add jldg` を実行する。5.3.6 の keychain は `oidc-prompt` が見つかると、内部の oidc-add に `--pw-prompt=gui` を付け、管理者の CLI 既定値を上書きするためである。以降の手動の oidc-add にまで影響する設定変更ではない。[5.3.6 の実装](https://github.com/indigo-dc/oidc-agent/blob/v5.3.6/src/oidc-keychain/oidc-keychain)

## 再ログイン時の自動接続・読み込み（任意）

初回登録後、毎回の手入力を省きたい利用者は、次を `~/.bashrc` に追加できる。自動設定は必須ではない。

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

対話端末を開くたびに接続し、必要なら保存済みアカウントを読み込む。この自動実行例では、毎回の PID と正常時の状態表示を抑えるため `>/dev/null` を付けている。標準エラーは表示し、接続確認に失敗した場合は復旧案内を出してアカウントを読み込まない。新しい agent への読み込みでは暗号化パスワードを求められる場合がある。再認証が必要なら `jldg-auth` を手動実行する。

これはシェル起動時の明示的な oidc-add 実行であり、トークン要求時の自動読み込みを止める `autoload: false` はそのままでよい。

Bash のログインシェルでは `~/.bash_profile` 等から `~/.bashrc` が読み込まれることを確認する。読み込まれない構成では、このブロックをログイン時の起動ファイルに置く。複数箇所へ重複して追加しない。tcsh の `~/.tcshrc` 用の例は [管理者マニュアル](ADMIN_GUIDE.md#57-tcsh) を参照する。シェル起動ファイルは本ツールが自動編集することはない。

## 初回登録と再認証

agent に接続できる端末で、次を直接実行する。Bash・tcsh のどちらからも同じコマンドを使う。`eval` や `source` は付けない。

初回登録が必要な場合も、refresh token が失効して再認証が必要と案内された場合も、次を使う。

```bash
jldg-auth
```

`oidc-gen --accounts` で保存済みの `jldg` アカウントを調べ、未登録なら初回登録、登録済みなら再認証を行う。一覧の取得に失敗した場合は処理を中止する。これは保存済み設定の有無の判定であり、agent への読み込み状態やトークンの有効性は判定しない。登録済みで実行すると、有効なアカウントでも再認証へ進む。単に未読み込みの場合は上記の `oidc-add` を使う。

初回登録の値は管理者が `/etc/oidc-agent/jldg-client.json` に、oidc-gen の共通オプションは `/etc/oidc-agent/jldg-auth.conf` に設定する。前者の標準配置先は `JLDG_CLIENT_CONFIG`、後者は `JLDG_AUTH_CONFIG` で変更できる。再認証は保存済みアカウントを使うため、クライアント JSON の読み取りは不要である。

パスワード・ブラウザ認証が必要なら端末上で案内する。helper はアカウントの通常の読み込みやトークン取得確認を行わない。登録・再認証の成功は対応する完了表示と終了状態0で確認する。

## ブラウザ認証と転送

どちらの場合も、**JLDG の証明書がインストールされたブラウザ**を使う。認証待ちの端末はそのままにする。

- **oidc-agent と同じマシンのブラウザ**：認証 URL を直接開く。この手順の SSH 転送や SOCKS proxy は不要である。
- **別 PC のブラウザ**：PC の別端末で、表示されたオプションを普段の SSH コマンドの接続先より前に追加する。ブラウザの SOCKS5 proxy を `localhost:1080` に設定し、SSH を維持したまま認証 URL を開く。

例えばコールバック用ポートが `4243` の場合、PC 側で次を実行する。

```bash
ssh -N -o ExitOnForwardFailure=yes -L 4243:localhost:4243 -D 1080 YOUR_SSH_HOST_ALIAS
```

接続先を実際の実行ホストに置き換え、普段必要なユーザー名・鍵・踏み台等も指定する。`-L` のポートは表示に合わせる。`-L` は localhost コールバック用、`-D 1080` は OP に実行ホスト経由で接続するための SOCKS proxy 用である。PC 側の両ポートが空いている必要がある。

`Please press Enter to try it again.` と表示されても準備中は押さず、**ブラウザ認証を完了してから元の端末で Enter を押す**。Enter は最後の1回の照会を行う操作である。OP 側の認証セッションが失効していたら、`jldg-auth` をやり直す。

元の端末の処理が完了したら、ブラウザの proxy 設定を元に戻し、転送端末を Ctrl-C で終了する。helper は SSH 接続の作成やブラウザ設定を自動では行わない。

## Gfarm のトークン取得と失敗時の操作

Gfarm は `JWT_USER_PATH` の指定により `jldg-token` を実行する。これは `oidc-token --time=60 jldg` を一度呼ぶだけのラッパーである。標準出力は成功時のトークンだけとし、失敗時は元のエラーと復旧方法を標準エラーへ表示して非0終了する。アプリケーションの標準入力は消費しない。

復旧方法は、状況に応じて利用者が端末で選ぶ。

| 状況 | 操作 |
|---|---|
| agent に接続できない | `oidc-keychain` で起動・再接続する（上記のシェル別手順） |
| 保存済みアカウントが未読み込み | `oidc-add jldg` |
| 初回登録・再認証が必要 | `jldg-auth` |
| OP への通信障害 | 通信を復旧してから再試行する |

復旧後に元の Gfarm コマンドを再実行する。ラッパーはエラー文から原因を決めつけず、起動・読み込み・登録・再認証・リトライを自動実行しない。バッチ実行でもブラウザ認証を開始しない運用のため、管理者は agent の自動読み込み・自動生成・自動再認証を無効にする。起動済み agent の設定は別途確認する。

有効なキャッシュがあればそのトークンを返し、更新が必要で refresh token が有効なら agent が通常の更新を行う。`--time=60` は残存有効時間の要求であり、トークンの寿命を60秒に設定するものではない。refresh token が失効しても、利用できるキャッシュが残っている間はトークン取得が成功する場合がある。

トークンを画面に表示しない確認方法：

```bash
jldg-token >/dev/null
```

## 中断・停止・再ログイン

- helper はパスワード入力前の端末設定を保存し、成功・失敗・Ctrl-C 等による終了時に復元する。入力文字が見えなくなったら `stty echo` を実行する。SIGKILL では復元できない。
- 登録・再認証を中断しても、agent やアカウントは自動で停止・削除・アンロードしない。環境変数も変更しない。認証失敗時は原因を解消してから明示的に再実行する。
- agent の停止は次のコマンドで行う。Bash・tcsh 共通であり、同じ利用者の他端末・他アカウントにも影響する。停止は発行済みトークンの取り消しではない。

  ```bash
  oidc-keychain --kill >/dev/null
  ```

  現在のシェルの接続用変数と `JWT_USER_PATH` は残る。再開時は上記と同じ `oidc-keychain` の接続手順を実行し、`oidc-add jldg` で読み込む。保存済みアカウントの再登録は不要である。
- ログアウトだけでは agent が残る場合がある。再ログイン後は上記の手順を手動または任意の起動設定で実行する。agent が残っていれば読み込み済みアカウントも再利用でき、新しく起動した場合は保存済みアカウントを読み込む。
- 同じアカウントの同時登録・同時再認証や、ホームを共有する複数ホスト間の競合は helper が制御しない。
- クライアント JSON は管理者が正しく設定済みであることを前提とし、helper は読み取り可否だけ確認する。復号パスワードを要求された場合は、管理者が JSON の構文・文字コードを確認する。
- 遅れて表示される oidc-gen の生成開始・受付の3行と失敗時の state 再照会コマンドの案内は抑制し、認証 URL・入力案内・失敗理由は表示する。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `jldg-auth` | 初回登録・再認証、転送案内、端末復元 |
| `jldg-token` | Gfarm 用のトークン取得と失敗時の操作案内 |
| `jldg-env.sh` / `jldg-env.csh` | 利用者が読み込む環境設定 |
| `jldg-auth.conf` | 管理者が指定する oidc-gen のオプション |
| `jldg-client.json` | 管理者が設定する public client 情報 |
| `issuer.config.d/jldg` | 暗号化パスワードのメモリ保持設定 |
