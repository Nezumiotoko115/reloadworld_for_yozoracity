Config = {}

Config.CommandName = 'reloadworld'
Config.UseAce = false
Config.AcePermission = 'reloadworld.use'
Config.EnhancedEnabled = true

Config.NormalTimeoutMs = 5000
Config.EnhancedTimeoutMs = 30000
Config.FadeDurationMs = 350
Config.CollisionRequestIntervalMs = 100
Config.EnhancedSceneRadius = 180.0

-- Enhanced mode uses GTA's player-switch streaming transition without moving the
-- player ped, then forces a fresh current-area scene, object and collision load.
-- This is intentionally slower and more disruptive than normal mode.
Config.EnhancedPlayerSwitchEnabled = true
Config.EnhancedInitialRequestMs = 1500
Config.EnhancedSwitchOutHoldMs = 6000
Config.EnhancedSwitchReturnTimeoutMs = 7000
Config.EnhancedLocalHoldMs = 8000
Config.EnhancedHdAreaEnabled = true
Config.EnhancedHdRadius = 250.0
Config.EnhancedLoadAllObjectsNow = true

Config.NormalCooldownSeconds = 60
Config.EnhancedCooldownSeconds = 10
Config.FeedbackExpirySeconds = 300

-- Safety: refuse unless the server can confirm that the ped was not already frozen.
Config.RequireKnownUnfrozenState = true

Config.Notifications = true
Config.Debug = false

Config.WorlddiagIntegration = true
Config.WorlddiagResourceName = 'worlddiag'
Config.WorlddiagPreDelayMs = 750

