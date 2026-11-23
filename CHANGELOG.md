# Changelog

## 未リリース - 2026-11-24

- `client_exception` の原因となったplayer-switch版を撤回し、動作していた1.1.0の遠方focus版へ復元
- `/reloadworld` から遠方focus版を直接実行し、クールダウン10秒を維持

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

