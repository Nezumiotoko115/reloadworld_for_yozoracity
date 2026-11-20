# worlddiag

ワールドストリーミング問題のオンデマンド診断値をJSON Linesへ記録するStandaloneリソースです。常時監視、自動原因判定、自動修復は行いません。

## 導入とACE

`worlddiag` フォルダーをresources内へ置きます。

```cfg
add_ace group.admin worlddiag.use allow
ensure worlddiag
ensure reloadworld
```

ACEはコマンドが実行される前にserver.cfgから適用してください。

## コマンド

- `/worldlog`: 管理者自身を診断。
- `/worldlog 15`: server ID 15を診断。

権限、対象、レート、同時数をサーバーで検証します。他プレイヤーへの通知は既定で有効です。対象画面のfade、固定、テレポートは行いません。

## ログ

保存先は `worlddiag/logs/YYYY-MM-DD.jsonl`（UTC）です。上限到達後は `-001`、`-002` のようにローテーションします。古いログは自動削除しません。各行が独立JSONで、`schema_version` と `type` を持ちます。

`logs/.gitignore` により、実運用で生成されたJSONLは既定でGit管理対象外になります。障害調査で共有する場合も、IP等は保存していない設計ですが、プレイヤー名・server ID・座標を含むため公開リポジトリへ直接コミットしないでください。

主なtype:

- `world_manual`: 手動診断
- `reload_before`: reload直前の採取要求
- `reload_result`: Native処理結果
- `reload_after`: reload後の採取要求
- `reload_feedback`: fixed/notfixedの主観的報告

同じreloadの行は `diagnostic_id` と `context.reload_id` / `reload.reload_id` で結合できます。座標やUTCの近接で複数プレイヤーの事例を比較できます。`client` はクライアント申告、`server` はサーバー観測です。

JSONL例（説明用に短縮）:

```json
{"schema_version":1,"utc":"2026-11-20T10:00:00Z","type":"reload_before","diagnostic_id":"rw-...","target_id":15,"client":{"position":{"x":1.0,"y":2.0,"z":3.0},"fps":{"estimated":59.8}},"server":{"ping_ms":42}}
```

## 設定

`config.lua` でコマンド、ACE、手動診断、reload連携、自動ログ、保存、対象通知、応答期限、レート、同時数、payload上限、ファイル上限、ローテーション、FPSサンプル数、debug、分類別フィールドを変更できます。不正な数値は安全な既定値へ戻します。`LogDirectory` は英数字、`_`、`-` だけを許可します。

## 分析の注意

FPSは `GetFrameTime` を既定30フレーム採取した算術平均から推定します。短時間値であり、診断採取そのものや瞬間変動の影響を受けます。`HasCollisionLoadedAroundEntity=true` は周辺コリジョンのNative状態であり、道路・建物の見た目が正しいことを保証しません。Ping、座標、移動、車両、before/after、主観的feedbackを組み合わせても、相関と原因を区別してください。

サーバー側だけで分かるMLO/YMAP/YTYP/YBN競合、ストリーミング予算、リソース構成をこのクライアント診断だけで特定することはできません。IP、Discord、license、Steam識別子は保存しません。

## セキュリティと容量管理

`request_id`、対象、送信元、期限、重複、型、数値範囲、NaN/Infinity、文字列長、JSONサイズをサーバーで検証します。クライアント値は検証後も信頼済み事実ではありません。連携exportは呼出元が `reloadworld` であることとサーバー内sessionを照合します。

ログ書込みは1キューで直列化し、自リソース内を `io.open(..., 'a')` で追記します。プロセス異常終了、OSクラッシュ、電源断に対する完全な原子性・flush保証はありません。定期バックアップ、容量監視、正常なstopを推奨します。保存失敗はコンソールへ出力され、手動診断では管理者へ通知されます。

## 取得できない／保証できない情報

- 実際に画面が溶けているかという客観判定
- GPU/VRAM/メモリ使用量の標準FiveM Nativeによる正確な値
- 個別マップファイルやresource競合の自動特定
- サーバーgame build（FXServerの `GetGameBuildNumber` は0の場合あり）
- beforeとafterがネットワーク遅延下で厳密に同じ時点条件になる保証

