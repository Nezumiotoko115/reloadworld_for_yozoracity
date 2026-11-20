Config = {}

Config.CommandName = 'worldlog'
Config.AcePermission = 'worlddiag.use'
Config.ManualDiagnosticsEnabled = true
Config.ReloadworldIntegration = true
Config.AutomaticDiagnosticLogs = true

Config.LogSavingEnabled = true
Config.NotifyTarget = true
Config.ResponseTimeoutMs = 5000
Config.ManualRateLimitSeconds = 30
Config.MaxConcurrentDiagnostics = 8
Config.MaxPendingPerTarget = 2
Config.MaxClientPayloadBytes = 32768

Config.LogDirectory = 'logs'
Config.MaxLogFileBytes = 5 * 1024 * 1024
Config.LogRotationEnabled = true
Config.MaxRotationFilesPerDay = 999

Config.FpsSampleCount = 30
Config.Debug = false

Config.Fields = {
    position = true,
    movement = true,
    vehicle = true,
    fps = true,
    collision = true,
    environment = true,
    server = true
}

