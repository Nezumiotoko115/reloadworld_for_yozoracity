# reloadworld

現在位置周辺のコリジョンとストリーミング要求を再実行するStandaloneリソースです。完全なワールド、MLO、YMAPの再読込や、表示不具合の修復を保証しません。

## 導入

`reloadworld` フォルダーをresources内へ置き、`server.cfg` に `ensure reloadworld` を追加します。`worlddiag` と併用する場合は先に `ensure worlddiag` を記述します。

## コマンド

- `/reloadworld`: 遠方focus経由の強化モード。プレイヤー座標は変えず、streaming focusを約8,000m遠方へ一時移動してから現在地のscene／collisionを再要求。
- `/reloadworld fixed`: 直近の実行で改善したという主観的報告。
- `/reloadworld notfixed`: 直近の実行で改善しなかったという主観的報告。

報告期限は既定5分、各reloadにつき1回です。未実行、期限切れ、重複、別プレイヤーの結果への報告は拒否します。

## 設定

`config.lua` でコマンド名、ACE、強化モード、通常／強化タイムアウト、フェード時間、要求間隔、遠方focusの距離・高さ・保持時間、現在地復帰後の保持時間、ロード半径、クールダウン、報告期限、通知、debug、worlddiag連携を変更できます。`/reloadworld` の既定クールダウンは10秒です。失敗・タイムアウトでも適用します。再接続およびリソース／サーバー再起動ではメモリ上のクールダウンと履歴は消えます。

強化モードの既定値は最大18秒、遠方focus保持4秒、現在地focus保持5秒です。プレイヤーped自体はテレポートしません。streaming focusを使う他resourceと競合する場合は、強化モードの使用タイミングを調整してください。

`UseAce=true` の場合:

```cfg
add_ace group.admin reloadworld.use allow
```

## 安全仕様

車両内と乗車途中、死亡／ペド消失、二重実行を拒否または中断します。車両操作、テレポート、無敵化は行いません。処理時だけペドを固定し、例外、タイムアウト、リソース停止でも固定解除・ロードシーン停止・フェードインを試みます。

`RequireKnownUnfrozenState=true`（既定）は、サーバー側でペドが未固定と確認できなければ実行しません。OneSyncやサーバーartifact構成によって確認できない場合、falseにすれば実行できますが、他リソースが事前に固定していたペドを最後に解除する危険があります。

## worlddiag連携

`worlddiag` がstarted状態のときだけserver exportを呼びます。未導入、停止、exportエラーはreloadのクリーンアップを妨げません。連携前待機はbefore計測用で、`WorlddiagPreDelayMs` から変更できます。

## トラブルシューティング

- 「固定状態を確認できない」: OneSyncとserver artifactを確認。安全性を理解した場合のみ上記設定を変更。
- 車両エラー: 完全に降車し、乗降アニメーション終了後に再実行。
- タイムアウト: 技術的完了が取れなかっただけで、表示状態とは別です。連打せず診断ログを採取。
- 多地点で街が溶ける: 強化モードはクライアントの現在地を強制再ストリーミングしますが、サーバー全体のstreaming負荷、巨大YMAP/YTYP/YBN、重いテクスチャ、resource競合、クライアントメモリ不足は直せません。複数人で再発する場合はworlddiagとresmon／profilerで根本原因を調査してください。
- 特定のバニラ建物だけ残る: 正式なロード対象なら強化処理後も再表示されます。該当IPLの `RemoveIpl`、YMAPの置換、map resource manifestを調査してください。
- 画面／固定が残る: `/reloadworld` 実行中にクライアントやresourceが強制終了した可能性があります。管理者へ連絡し、競合リソースも確認してください。

