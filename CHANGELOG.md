# Changelog

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

