Config = {}

Config.CommandName = 'reloadworld'
Config.UseAce = false
Config.AcePermission = 'reloadworld.use'
Config.EnhancedEnabled = true

Config.NormalTimeoutMs = 5000
Config.EnhancedTimeoutMs = 18000
Config.FadeDurationMs = 350
Config.CollisionRequestIntervalMs = 100
Config.EnhancedSceneRadius = 120.0

-- Enhanced mode performs an experimental "cold cycle" without teleporting:
-- temporarily move streaming focus far away, hold it, then focus and reload the
-- player's current area. This cannot guarantee that vanilla map entities unload.
Config.EnhancedColdCycleEnabled = true
Config.EnhancedInitialRequestMs = 1500
Config.EnhancedRemoteFocusDistance = 8000.0
Config.EnhancedRemoteFocusHeight = 1000.0
Config.EnhancedRemoteSceneRadius = 50.0
Config.EnhancedRemoteHoldMs = 4000
Config.EnhancedReturnHoldMs = 5000

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

