# Changelog

## 1.3.2 - 2026-11-22

- v1.3.xの内部mode／設定名リファクタリングを取り消し、動作実績のあるv1.2.0 Enhancedクライアント経路を復元
- 公開コマンド `/reloadworld` から内部mode `enhanced` を直接呼ぶ最小差分へ変更
- `/reloadworld enhanced` 引数は引き続き廃止
- 既定クールダウンを10秒へ変更

## 1.3.1 - 2026-11-21

- 標準 `/reloadworld` の既定クールダウンを120秒から20秒へ変更

## 1.3.0 - 2026-11-21

- v1.2.0の `/reloadworld enhanced` 処理を標準 `/reloadworld` へ昇格
- `/reloadworld enhanced` 引数を廃止し、reloadを単一モード化
- 標準処理を最大30秒、既定クールダウン120秒へ統一
- `Enhanced*` / `Normal*` 設定を単一モード向けの設定名へ整理
- コマンド一覧、導入手順、トラブルシューティング、検証手順を単一モード前提へ更新

## 1.2.0 - 2026-11-21

- 遠方focusだけでは改善しない多地点の街溶け対策として、強化モードを全面更新
- プレイヤー座標を変えず `SwitchToMultiFirstPart` / `SwitchToMultiSecondPart` でstreaming遷移を実行
- 現在地へ `SetHdArea`、`SetFocusPosAndVel`、`LoadScene`、`LoadAllObjectsNow`、`NewLoadSceneStartSphere` を段階適用
- 強化最大待機を30秒、スイッチアウト保持6秒、復帰待機最大7秒、現在地保持8秒へ変更
- 既存プレイヤースイッチ中の実行を拒否し、例外時は `StopPlayerSwitch`、`ClearHdArea`、`NewLoadSceneStop`、`ClearFocus` を試行
- `player_switch` と `local_stream` の段階結果をworlddiagへ記録
- 多地点・複数人で再発する場合のサーバー／map asset側調査手順を追加

## 1.1.0 - 2026-11-21

- `/reloadworld enhanced` を、コリジョン状態が既にloadedでも必ず実行する方式へ変更
- プレイヤーをテレポートせず、`SetFocusPosAndVel` で約8,000m遠方へstreaming focusを一時移動
- 遠方focusを既定4秒保持後、現在地focusを既定5秒保持して再ストリーミング
- 強化モード最大待機を10秒から18秒へ変更
- 例外、timeout、resource stop時に `NewLoadSceneStop` と `ClearFocus` を試行
- `cold_cycle` と `return_stream` の段階結果をworlddiagへ記録
- バニラIPL/YMAPが正式なロード対象の場合は再表示される制限をREADMEへ追記

## 1.0.0 - 2026-11-20

- reloadworld / worlddiag 初版

