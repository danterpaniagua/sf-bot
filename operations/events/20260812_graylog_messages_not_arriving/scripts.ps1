# Event: 20260812_graylog_messages_not_arriving
# Run on SFCG-SMTP-01 / SFCG-SMTP-02 (hMailServer relay VMs, service SF-SMTPRL)
# Commands are grouped by phase: Investigation / Audit
# No remediation commands run directly on these VMs — the fix is on the OpenSearch side (see scripts.sh)

# === INVESTIGATION ===

# C1 — Hostname stamp (always run first — two VMs involved, never assume which one an RDP/SSH session is on)
"Running on: $env:COMPUTERNAME"

# C11 — List hMailServer log files matched by the NXLog wildcard (found ~80 historical files back to Oct 2024)
Get-ChildItem 'C:\Program Files (x86)\hMailServer\Logs' | Sort-Object LastWriteTime -Descending | Select-Object Name, Length, LastWriteTime

# Attempt to archive old log files out of the wildcard's reach (blocked by Program Files UAC permissions — never completed, line of investigation abandoned once the real cause was found)
$logsPath = 'C:\Program Files (x86)\hMailServer\Logs'
$archivePath = Join-Path $logsPath 'archive'
New-Item -ItemType Directory -Path $archivePath -Force | Out-Null
Get-ChildItem $logsPath -Filter 'hmailserver_*.log' |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) } |
    Move-Item -Destination $archivePath
Get-ChildItem $logsPath -Filter '*.log'

# === AUDIT ===

# C10 — Manual raw UDP test send to Graylog's TXT_UDP input, bypassing NXLog/hMailServer entirely
"Running on: $env:COMPUTERNAME"
$udpClient = New-Object System.Net.Sockets.UdpClient
$testMessage = "PWSH-UDP-TEST from $env:COMPUTERNAME at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($testMessage)
$udpClient.Send($bytes, $bytes.Length, "3.214.234.76", 1514) | Out-Null
$udpClient.Close()
"Sent: $testMessage"
# Result: arrived in Graylog within ~1 second — network path confirmed healthy, root cause was not network-related
