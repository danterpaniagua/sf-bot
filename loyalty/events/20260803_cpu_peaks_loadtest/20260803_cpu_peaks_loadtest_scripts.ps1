# Event: 20260803_cpu_peaks_loadtest
# Run directly on SFCG-DB01 (RDP / remote PowerShell session) — OS-level checks, not queryable from PNSSRL

# P1 — Windows Update install history (checks for an update install overlapping the peak windows)
$Session = New-Object -ComObject Microsoft.Update.Session
$Searcher = $Session.CreateUpdateSearcher()
$HistoryCount = $Searcher.GetTotalHistoryCount()
$Searcher.QueryHistory(0, $HistoryCount) |
    Select-Object Title, Date, ResultCode |
    Sort-Object Date -Descending |
    Select-Object -First 30

# P2 — Windows Defender real-time scan check — event log + scan status
# Window: 2026-08-03 12:00-18:30 GMT (covers all three CPU peaks; OS local time = GMT per infra doc)

# P2a. Defender operational events in the investigated window
Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-Windows Defender/Operational'
    StartTime = '2026-08-03 12:00:00'
    EndTime   = '2026-08-03 18:30:00'
} | Select-Object TimeCreated, Id, LevelDisplayName, Message | Sort-Object TimeCreated | Format-Table -Wrap

# P2b. Current scan status/history (last full/quick scan times, signature age)
Get-MpComputerStatus | Select-Object AntivirusEnabled, RealTimeProtectionEnabled, `
    QuickScanStartTime, QuickScanEndTime, `
    FullScanStartTime, FullScanEndTime, `
    LastFullScanSource, LastQuickScanSource, `
    AntivirusSignatureLastUpdated

# P2c. Any threat detections around the window
Get-MpThreatDetection | Where-Object { $_.InitialDetectionTime -ge '2026-08-03 12:00:00' -and $_.InitialDetectionTime -le '2026-08-03 18:30:00' } |
    Select-Object InitialDetectionTime, ThreatID, ProcessName, Resources

# --- Post-closure follow-up: is an existing collector, or a scheduled task, the source of peaks 2/3? ---

# P3a — List all Data Collector Sets on this machine (built-in + user-defined)
logman query

# P3b/P3d — Inspect the two pre-existing Trace collectors found (GAEvents, RTEvents)
logman query GAEvents -ets
logman query RTEvents -ets

# P3e — Confirm SQL IaaS Extension / Azure Guest Agent services are present
Get-Service | Where-Object { $_.DisplayName -match 'Azure|Guest Agent|SqlIaaS' } | Select-Object Name, DisplayName, Status

# P3c — Any Scheduled Task with a trigger firing during the investigated window
Get-ScheduledTask | ForEach-Object {
    $info = $_ | Get-ScheduledTaskInfo
    [PSCustomObject]@{
        TaskName    = $_.TaskName
        TaskPath    = $_.TaskPath
        State       = $_.State
        LastRunTime = $info.LastRunTime
        LastResult  = $info.LastTaskResult
    }
} | Where-Object {
    $_.LastRunTime -ge [datetime]'2026-08-03 12:00:00' -and $_.LastRunTime -le [datetime]'2026-08-03 18:30:00'
} | Sort-Object LastRunTime | Format-Table -AutoSize

# P3f — LastRunTime for all custom SmartFran scheduled tasks
Get-ScheduledTask -TaskPath '\SmartFran\' | ForEach-Object {
    $info = $_ | Get-ScheduledTaskInfo
    [PSCustomObject]@{
        TaskName    = $_.TaskName
        State       = $_.State
        LastRunTime = $info.LastRunTime
        LastResult  = $info.LastTaskResult
        NextRunTime = $info.NextRunTime
    }
} | Sort-Object LastRunTime -Descending | Format-Table -AutoSize

# P3g — CustomerPointLog_to_BlobStorage's actual trigger schedule
(Get-ScheduledTask -TaskName 'CustomerPointLog_to_BlobStorage' -TaskPath '\SmartFran\').Triggers |
    Select-Object StartBoundary, Enabled, Repetition

# --- Ongoing safety net: continuous per-process / per-core CPU logging (always-on, circular buffer) ---

# CPUWatch — created and started 2026-08-03, still running
logman create counter CPUWatch `
    -si 15 `
    -f bincirc -max 500 `
    -o C:\PerfLogs\CPUWatch\CPUWatch `
    -c "\Process(*)\% Processor Time" "\Process(*)\ID Process" `
       "\Processor(*)\% Processor Time" "\Processor(*)\% User Time" "\Processor(*)\% Privileged Time"
logman start CPUWatch
