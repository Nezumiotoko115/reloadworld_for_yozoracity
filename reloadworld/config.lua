Config = {}

Config.CommandName = 'reloadworld'
Config.UseAce = false
Config.AcePermission = 'reloadworld.use'
Config.EnhancedEnabled = true

Config.NormalTimeoutMs = 5000
Config.EnhancedTimeoutMs = 10000
Config.FadeDurationMs = 350
Config.CollisionRequestIntervalMs = 100
Config.EnhancedSceneRadius = 120.0

Config.NormalCooldownSeconds = 60
Config.EnhancedCooldownSeconds = 120
Config.FeedbackExpirySeconds = 300

-- Safety: refuse unless the server can confirm that the ped was not already frozen.
Config.RequireKnownUnfrozenState = true

Config.Notifications = true
Config.Debug = false

Config.WorlddiagIntegration = true
Config.WorlddiagResourceName = 'worlddiag'
Config.WorlddiagPreDelayMs = 750

