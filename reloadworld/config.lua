Config = {}

Config.CommandName = 'reloadworld'
Config.UseAce = false
Config.AcePermission = 'reloadworld.use'

Config.TimeoutMs = 30000
Config.FadeDurationMs = 350
Config.CollisionRequestIntervalMs = 100
Config.SceneRadius = 180.0

-- Standard /reloadworld uses GTA's player-switch streaming transition without
-- moving the player ped, then forces a fresh current-area scene, object and
-- collision load. This intentionally takes around 20 seconds.
Config.PlayerSwitchEnabled = true
Config.InitialRequestMs = 1500
Config.SwitchOutHoldMs = 6000
Config.SwitchReturnTimeoutMs = 7000
Config.LocalHoldMs = 8000
Config.HdAreaEnabled = true
Config.HdRadius = 250.0
Config.LoadAllObjectsNow = true

Config.CooldownSeconds = 120
Config.FeedbackExpirySeconds = 300

-- Safety: refuse unless the server can confirm that the ped was not already frozen.
Config.RequireKnownUnfrozenState = true

Config.Notifications = true
Config.Debug = false

Config.WorlddiagIntegration = true
Config.WorlddiagResourceName = 'worlddiag'
Config.WorlddiagPreDelayMs = 750

