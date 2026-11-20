# reloadworld / worlddiag

FiveM向けStandalone Luaリソース2点です。`reloadworld` は現在位置周辺のコリジョン／ストリーミング要求を安全側でやり直す一時改善ツール、`worlddiag` は手動または連携時だけ診断値を採取してJSON Linesへ保存する調査ツールです。ESX、QBCore、Qbox、ox_libには依存しません。

- [導入・運用手順書](導入・運用手順書.md)
- [最終確認レポート](最終確認レポート.md)
- [変更履歴](CHANGELOG.md)

## 1. 技術的な実現可能性

完全なワールド、MLO、YMAPを任意に強制再読込する公式APIは確認できません。この実装が行うのは、現在位置でのコリジョン要求と、強化モード時の遠方focus経由・追加ロードシーン要求です。プレイヤー座標は変更しません。Nativeの完了値は「街が直った」ことを示しません。

主要API（いずれもCfx.re公式ドキュメントまたは公式Nativeリポジトリで確認）:

| API | 実行側 | シグネチャ／戻り値 | 用途と制限 |
|---|---|---|---|
| `RequestCollisionAtCoord` | client | `(x, y, z) -> void` | 指定座標のコリジョンを要求。表示改善の保証なし |
| `RequestAdditionalCollisionAtCoord` | client | `(x, y, z) -> void` | 追加のコリジョン要求。完了値なし |
| `HasCollisionLoadedAroundEntity` | client | `(entity) -> bool` | エンティティ周辺のコリジョン状態。画面上の完全性は判定しない |
| `NewLoadSceneStart` | client | `(pos, offset, radius, p7) -> bool` | 強化処理開始。`p7=0`。成功は改善を意味しない |
| `IsNewLoadSceneLoaded` / `NewLoadSceneStop` | client | `() -> bool` / `() -> void` | 追加ロードシーンの確認／必須終了処理 |
| `SetFocusPosAndVel` / `ClearFocus` | client | `(pos, offset) -> void` / `() -> void` | 強化モードで遠方と現在地のストリーミングfocusを切替。プレイヤーは移動しない |
| `DoScreenFadeOut/In`, `IsScreenFadedOut` | client | fade ms / bool | 画面遷移。例外時も復帰を試行 |
| `FreezeEntityPosition` | client | `(entity, bool) -> void` | ペドのみ一時固定。車両は操作しない |
| `IsPedInAnyVehicle`, `IsPedGettingIntoAVehicle`, `IsPedJumpingOutOfVehicle` | client | `(ped) -> bool` | 車内、乗車中、飛び降り中を安全側で拒否 |
| `IsEntityPositionFrozen` | server CFX | `(entity) -> bool` | 既存固定の保護。状態を確認できない場合は既定で実行拒否 |
| `GetFrameTime` | client | `() -> seconds` | 連続フレームの算術平均からFPSを推定 |
| `GetGameBuildNumber` | shared CFX | `() -> int` | クライアントではゲームビルド。FXServerでは0になり得る |
| `GetPlayerPing` | server | `(source) -> int` | サーバー観測のPing |
| `IsPlayerAceAllowed` | server | `(source, object) -> bool` | `/worldlog` の認可 |
| `GetInvokingResource` | server/shared CFX | `() -> string?` | `worlddiag` exportを呼んだリソース名の確認 |
| `io.open` (sandbox) | server | `r` / `a` 等 | 自リソース内への追記。別リソースや `..` はsandboxで拒否 |

公式資料:

- [Native reference](https://docs.fivem.net/natives/)
- [REQUEST_COLLISION_AT_COORD](https://github.com/citizenfx/natives/blob/master/STREAMING/RequestCollisionAtCoord.md)
- [REQUEST_ADDITIONAL_COLLISION_AT_COORD](https://github.com/citizenfx/natives/blob/master/STREAMING/RequestAdditionalCollisionAtCoord.md)
- [HAS_COLLISION_LOADED_AROUND_ENTITY](https://github.com/citizenfx/natives/blob/master/STREAMING/HasCollisionLoadedAroundEntity.md)
- [NEW_LOAD_SCENE_START](https://github.com/citizenfx/natives/blob/master/STREAMING/NewLoadSceneStart.md)
- [IS_NEW_LOAD_SCENE_LOADED](https://github.com/citizenfx/natives/blob/master/STREAMING/IsNewLoadSceneLoaded.md)
- [NEW_LOAD_SCENE_STOP](https://github.com/citizenfx/natives/blob/master/STREAMING/NewLoadSceneStop.md)
- [SET_FOCUS_POS_AND_VEL](https://github.com/citizenfx/natives/blob/master/STREAMING/SetFocusPosAndVel.md)
- [FREEZE_ENTITY_POSITION](https://github.com/citizenfx/natives/blob/master/ENTITY/FreezeEntityPosition.md)
- [IS_ENTITY_POSITION_FROZEN](https://docs.fivem.net/natives/?_0xEDBE6ADD)
- [IS_PED_JUMPING_OUT_OF_VEHICLE](https://github.com/citizenfx/natives/blob/master/PED/IsPedJumpingOutOfVehicle.md)
- [RegisterCommand / ACL](https://docs.fivem.net/docs/scripting-manual/migrating-from-deprecated/creating-commands/)
- [Server commands / add_ace / ensure](https://docs.fivem.net/docs/server-manual/server-commands/)
- [Resource manifest and exports](https://docs.fivem.net/docs/scripting-reference/resource-manifest/)
- [Resource sandbox and file append](https://docs.fivem.net/docs/developers/sandbox/)

## 2. システム設計

`reloadworld` のコマンド入口、クールダウン、二重実行、履歴、報告期限はサーバーが所有します。クライアントはサーバーが発行した `reload_id` に対する処理だけを実行し、結果を同じIDで返します。強化モードはコリジョンが既にloadedでも、遠方focus保持、現在地focus復帰、現在地ロード確認を必ず実施します。安全な後処理は1つのcleanup関数へ集約し、ロードシーン停止と `ClearFocus` も例外時に試行します。

`worlddiag` はサーバーが `diagnostic_id` と `request_id` を発行し、対象・期限・送信元を照合します。クライアント値は型、範囲、文字列長、JSONサイズを検証します。IP、license、Discord、Steam識別子は取得も保存もしません。

任意連携はサーバーexport `BeginReload`、`EndReload`、`RecordFeedback` だけで行います。`worlddiag` は `GetInvokingResource()` が `reloadworld` の場合だけ受け付けます。各リソースは相手が停止／未導入でも単独動作します。before採取要求を先に送信し、既定750ms後にリロードを開始しますが、ネットワークや低FPSにより計測が重なる可能性はログの時刻・計測時間から判別してください。

## 3. インストール

2つのフォルダーをサーバーの `resources/[local]/` などへコピーし、`server.cfg` に追加します。

```cfg
add_ace group.admin worlddiag.use allow

ensure worlddiag
ensure reloadworld
```

`worlddiag` を先に起動すると連携開始時点から利用できます。起動順は依存関係ではなく、`reloadworld` は都度 `GetResourceState` で稼働を確認します。`reloadworld` 自体もACE必須にする場合は `reloadworld/config.lua` の `UseAce = true` とし、次を追加します。

```cfg
add_ace group.admin reloadworld.use allow
```

## 4. FiveM実機テスト手順

1. 各リソースを単独で `ensure` し、コンソールエラーがないことを確認する。
2. 権限なし／ありのユーザーで `/worldlog` と `/worldlog [serverId]` を試す。
3. 徒歩で `/reloadworld`、`/reloadworld enhanced` を実行し、フェード、固定解除、通知、クールダウンを確認する。
4. 車両内、乗車途中、死亡時、既に固定された状態で拒否または安全終了することを確認する。
5. 処理中に `stop reloadworld` を行い、可能な範囲で画面と固定が復元されることを確認する。
6. `worlddiag` を停止した状態でreloadとfeedbackが機能すること、`reloadworld` 停止時に手動診断が機能することを確認する。
7. 両方を起動し、同じ `diagnostic_id` で `reload_before`、`reload_result`、`reload_after`、`reload_feedback` が記録されることを確認する。
8. 対象切断、応答タイムアウト、連打、偽のrequest ID、重複応答を試し、受理されないことを確認する。
9. 小さい `MaxLogFileBytes` でローテーションを確認する。

## 5. 検証範囲と既知の制限

静的なLua構文、manifest、イベント名、設定初期値、ZIP内容は開発環境で検査します。FiveM/GTA V実機でのNative挙動、OneSync構成差、実際の街の表示改善、負荷時のファイルI/Oはこの環境では未検証です。

- `RequireKnownUnfrozenState=true` では、サーバーがペドと固定状態を確認できない構成でreloadを拒否します。既存リソースの固定解除を防ぐための安全側の仕様です。
- 強化モードのfocus切替はアンロードを保証せず、script camera、spectate、cutscene等が独自focusを使用中の場合は競合し得ます。
- バニラ建物がIPL/YMAP上で正式なロード対象なら、遠方focus後も現在地へ戻した時点で再表示されます。その場合はmap resource側の除去・置換設定が根本修正です。
- ペド固定確認からクライアント固定までに他リソースが状態を変える競合は、完全には排除できません。
- FPSは短時間の推定値です。Pingとコリジョン状態を含め、単独で原因や改善を証明しません。
- クライアント送信値は改ざん可能です。サーバー観測値と区別して保存します。
- JSONLは同一プロセス内で直列化し `a` モードで追記しますが、OS／電源断時の完全な原子性や永続化は保証できません。
- 自動原因判定、マップファイル競合検出、リソース再起動、サーバー設定変更、テレポート、無敵化は行いません。

