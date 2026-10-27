<#
.SYNOPSIS
  GITIN-2270: auditoria de un notebook (SOLO LECTURA). Guarda todo en una carpeta nueva dentro de la carpeta donde se ejecuta
  y genera un informe HTML.

.DESCRIPTION
  Crea la carpeta  audit-<HOSTNAME>-<fecha>Z  en la carpeta actual (o en -OutDir) con:
    report.html            informe para leer (autocontenido, sin conexion a internet)
    report.json            todos los datos juntos
    run.log                registro de la ejecucion del script (secciones, tiempos, errores)
    csv\*.csv              una tabla por seccion: aplicaciones, procesos, modulos de RAM, discos, adaptadores de red,
                           eventos de navegador, reportes de cierre de navegador, eventos WLAN
    wlan-networks.txt      salida cruda de "netsh wlan show networks mode=bssid" (redes vecinas; incluye sus nombres)
    wlan-interfaces.txt    salida cruda de "netsh wlan show interfaces" (WiFi actual: senal, canal, tipo de radio)
    routes.csv, ip-interfaces.csv, vpn-connections.csv, proxy.csv, proxy-winhttp.txt  tabla de rutas IPv4, metricas de las interfaces, perfiles de VPN de Windows (solo lectura) y proxy
    ping-results.csv       prueba de ping y jitter al gateway (muestras en la columna SamplesMs)
    windows-update-*.csv   Windows Update: historial y actualizaciones instaladas
    av-*.csv, defender-*.csv  antivirus: productos, amenazas detectadas y eventos de Defender (solo lectura; no inicia ningun analisis)
    events-*.csv           Visor de eventos: resumen por proveedor/id, ultimos eventos y ultimos indicadores de caida
  Datos: hostname, modelo, CPU, RAM (total, libre, modulos y velocidades), estado de discos (SMART segun Windows),
  procesos con CPU y RAM, aplicaciones instaladas con ultimo uso aproximado, navegadores y versiones, eventos de falla/cuelgue
  de navegadores, Windows Update (ultima busqueda e instalacion exitosas, historial, KB instaladas, reinicio pendiente), antivirus (productos registrados, estado de Microsoft Defender, amenazas detectadas y eventos de Defender),
  errores/advertencias recientes del Visor de eventos (System y Application) e indicadores de caidas,
  adaptadores de red con version de controlador, eventos de conexion/desconexion WiFi, SSID conectado,
  banda (2.4/5 GHz), canal y saturacion de canales segun las redes vecinas, gateway predeterminado y prueba de ping y jitter contra el gateway y contra Cloudflare (ICMP a 1.1.1.1 y peticiones HTTPS a speed.cloudflare.com) (jitter = promedio de la diferencia entre
  tiempos de ida y vuelta consecutivos; resolucion de 1 ms).
  NO cambia nada del equipo. Usa la red solo para pings ICMP al gateway y a 1.1.1.1 (Cloudflare) y para unas pocas peticiones HTTPS vacias a speed.cloudflare.com (-SkipInternet las omite; -HttpJitterCount 0 omite solo las HTTPS). NO lee historial de navegacion, cookies, contrasenas ni URLs. De los
  "logs de navegador" solo toma los eventos de Windows de falla/cuelgue y los metadatos de los archivos de reportes de
  cierre (sin abrirlos). Los procesos se listan sin linea de comandos.

.NOTES
  Disenado para Windows 10 (1809 o superior) y Windows 11 con Windows PowerShell 5.1 (tambien corre en PowerShell 7 con Windows).
  No usa wmic ni Win32_Product (no existen o son lentos en Windows 11 recientes). Todavia no fue probado en ningun equipo.
  De preferencia ejecutar como administrador (sin eso faltan datos de SMART, Prefetch y de algunos procesos;
  el informe lo indica en "Notas"). "Ultimo uso" es una aproximacion (Prefetch + UserAssist); puede quedar "desconocido".
  Uso:  powershell -ExecutionPolicy Bypass -File .\audit-laptop.ps1 [-OutDir C:\Temp] [-SampleSeconds 5] [-PingCount 50] [-PingIntervalMs 200] [-PingTargets 8.8.8.8] [-Open]
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutDir = (Get-Location).Path,
    [int]$SampleSeconds = 5,
    [int]$TopProcesses = 15,
    [int]$EventDays = 14,
    [int]$MaxEventsRead = 3000,
    [int]$PingCount = 50,
    [int]$PingIntervalMs = 200,
    [string[]]$PingTargets = @('1.1.1.1'),
    [int]$HttpJitterCount = 30,
    [string]$CloudflareUrl = 'https://speed.cloudflare.com/__down?bytes=0',
    [switch]$SkipInternet,
    [switch]$Open
)

$ErrorActionPreference = 'Continue'
$notes = New-Object System.Collections.Generic.List[string]
$hostName = $env:COMPUTERNAME
$startUtc = (Get-Date).ToUniversalTime()
$stamp = $startUtc.ToString('yyyyMMddTHHmmss') + 'Z'
$runDir = Join-Path $OutDir ("audit-{0}-{1}" -f $hostName, $stamp)
$csvDir = Join-Path $runDir 'csv'
New-Item -ItemType Directory -Path $csvDir -Force | Out-Null
$logFile = Join-Path $runDir 'run.log'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Log([string]$msg) {
    $line = '{0} {1}' -f (Get-Date).ToUniversalTime().ToString('s'), $msg
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Host $line
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Log "Auditoria en $hostName | administrador: $isAdmin | PowerShell $($PSVersionTable.PSVersion) | carpeta: $runDir"
if (-not $isAdmin) { $notes.Add('Sin permisos de administrador: SMART parcial, Prefetch no leido y algunos procesos sin datos de CPU.') }

function Hide-UserPath([string]$p) {
    if ([string]::IsNullOrEmpty($p)) { return $p }
    $u = $env:USERPROFILE
    if ($u) { return $p.Replace($u, '%USERPROFILE%') }
    return $p
}

# Los acentos del informe se escriben en el codigo como ~a~ ~e~ ~i~ ~o~ ~u~ ~n~ (~U~ = U con tilde, ~ue~ = u con dieresis) para que
# el archivo sea ASCII puro y no se rompa si PowerShell 5.1 lo lee como ANSI; se convierten en tiempo de ejecucion.
# Ojo: las tablas hash de PowerShell no distinguen mayusculas, por eso se usa una Hashtable con comparador Ordinal (a y A son claves distintas).
$script:AccentMap = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
$script:AccentMap.Add('a', [string][char]0x00E1); $script:AccentMap.Add('e', [string][char]0x00E9); $script:AccentMap.Add('i', [string][char]0x00ED)
$script:AccentMap.Add('o', [string][char]0x00F3); $script:AccentMap.Add('u', [string][char]0x00FA); $script:AccentMap.Add('n', [string][char]0x00F1)
$script:AccentMap.Add('A', [string][char]0x00C1); $script:AccentMap.Add('E', [string][char]0x00C9); $script:AccentMap.Add('I', [string][char]0x00CD)
$script:AccentMap.Add('O', [string][char]0x00D3); $script:AccentMap.Add('U', [string][char]0x00DA); $script:AccentMap.Add('N', [string][char]0x00D1)
$script:AccentMap.Add('ue', [string][char]0x00FC)
function Add-Accents([string]$t) {
    if ([string]::IsNullOrEmpty($t)) { return $t }
    return [regex]::Replace($t, '~(ue|[aeiounAEIOUN])~', [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $script:AccentMap[$m.Groups[1].Value] })
}

function ConvertFrom-Rot13([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $c = [int][char]$ch
        if ($c -ge 65 -and $c -le 90) { [void]$sb.Append([char]((($c - 65 + 13) % 26) + 65)) }
        elseif ($c -ge 97 -and $c -le 122) { [void]$sb.Append([char]((($c - 97 + 13) % 26) + 97)) }
        else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

function Write-Failure([string]$What, $ErrRecord) {
    Write-Log ("FALLO {0}: {1}" -f $What, $ErrRecord.Exception.Message)
    try { Add-Content -Path $logFile -Encoding UTF8 -Value ("      en linea {0}: {1}" -f $ErrRecord.InvocationInfo.ScriptLineNumber, ($ErrRecord.InvocationInfo.Line -replace '\s+', ' ').Trim()) } catch { }
    try { Add-Content -Path $logFile -Encoding UTF8 -Value ("      tipo: {0}" -f $ErrRecord.Exception.GetType().FullName) } catch { }
    try { Add-Content -Path $logFile -Encoding UTF8 -Value ("      pila: " + (($ErrRecord.ScriptStackTrace -split "`r?`n") -join ' <- ')) } catch { }
}
function Get-Section([string]$Name, [scriptblock]$Block) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $r = & $Block
        Write-Log ("OK    {0} ({1} ms)" -f $Name, $sw.ElapsedMilliseconds)
        return $r
    } catch {
        $m = "Seccion '$Name' fallo: $($_.Exception.Message)"
        $notes.Add($m); Write-Log ("FALLO {0}" -f $m)
        # donde fallo (linea y pila), solo en run.log para poder corregirlo sin adivinar
        try { Add-Content -Path $logFile -Encoding UTF8 -Value ("      en linea {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, ($_.InvocationInfo.Line -replace '\s+', ' ').Trim()) } catch { }
        try { Add-Content -Path $logFile -Encoding UTF8 -Value ("      pila: " + (($_.ScriptStackTrace -split "`r?`n") -join ' <- ')) } catch { }
        return $null
    }
}

function Export-Table($rows, [string]$file) {
    $rows = @($rows | Where-Object { $null -ne $_ })
    if ($rows.Count -gt 0) { $rows | Export-Csv -Path (Join-Path $csvDir $file) -NoTypeInformation -Encoding UTF8 }
}

# ---------- 1. Equipo ----------
$system = Get-Section 'equipo' {
    $cs = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $bios = Get-CimInstance Win32_BIOS
    [pscustomobject]@{
        Hostname        = $hostName
        Manufacturer    = $cs.Manufacturer
        Model           = $cs.Model
        SerialNumber    = $bios.SerialNumber
        BiosVersion     = $bios.SMBIOSBIOSVersion
        OperatingSystem = $os.Caption
        OsVersion       = $os.Version
        WindowsFamily   = $(if ([int]($os.BuildNumber) -ge 22000) { 'Windows 11' } else { 'Windows 10' })
        BuildNumber     = $os.BuildNumber
        DisplayVersion  = $(try { $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; if ($cv.PSObject.Properties['DisplayVersion']) { $cv.DisplayVersion } else { $cv.ReleaseId } } catch { $null })
        LastBootUtc     = $os.LastBootUpTime.ToUniversalTime().ToString('s') + 'Z'
        TimeZone        = (Get-TimeZone).Id
    }
}

# ---------- 2. CPU ----------
$cpu = Get-Section 'cpu' {
    @(Get-CimInstance Win32_Processor | ForEach-Object {
        [pscustomobject]@{
            Name              = ($_.Name -replace '\s+', ' ').Trim()
            Cores             = $_.NumberOfCores
            LogicalProcessors = $_.NumberOfLogicalProcessors
            MaxClockMHz       = $_.MaxClockSpeed
            CurrentClockMHz   = $_.CurrentClockSpeed
            LoadPercentNow    = $_.LoadPercentage
        }
    })
}

# ---------- 3. RAM ----------
$memory = Get-Section 'ram' {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeGb = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $modules = @(Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        [pscustomobject]@{
            Slot               = $_.DeviceLocator
            Bank               = $_.BankLabel
            Manufacturer       = ($_.Manufacturer + '').Trim()
            PartNumber         = ($_.PartNumber + '').Trim()
            CapacityGB         = [math]::Round($_.Capacity / 1GB, 2)
            SpeedMHz           = $_.Speed
            ConfiguredSpeedMHz = $_.ConfiguredClockSpeed
            SmbiosMemoryType   = $_.SMBIOSMemoryType
            FormFactor         = $_.FormFactor
        }
    })
    [pscustomobject]@{
        TotalGB     = $totalGb
        AvailableGB = $freeGb
        UsedPercent = [math]::Round(100 * ($totalGb - $freeGb) / $totalGb, 1)
        ModuleCount = $modules.Count
        Modules     = $modules
    }
}

# ---------- 4. Discos (SMART segun Windows) ----------
$disks = Get-Section 'discos' {
    $list = @(Get-PhysicalDisk | ForEach-Object {
        $rel = $null
        try { $rel = $_ | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
        [pscustomobject]@{
            Name              = $_.FriendlyName
            MediaType         = $_.MediaType
            BusType           = $_.BusType
            SizeGB            = [math]::Round($_.Size / 1GB, 1)
            HealthStatus      = $_.HealthStatus
            OperationalStatus = ($_.OperationalStatus -join ',')
            TemperatureC      = if ($rel) { $rel.Temperature } else { $null }
            WearPercent       = if ($rel) { $rel.Wear } else { $null }
            PowerOnHours      = if ($rel) { $rel.PowerOnHours } else { $null }
            ReadErrorsTotal   = if ($rel) { $rel.ReadErrorsTotal } else { $null }
            WriteErrorsTotal  = if ($rel) { $rel.WriteErrorsTotal } else { $null }
        }
    })
    $predict = @()
    try {
        $predict = @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop |
            ForEach-Object { [pscustomobject]@{ Instance = $_.InstanceName; PredictFailure = $_.PredictFailure } })
    } catch { $notes.Add('MSStorageDriver_FailurePredictStatus no disponible (permisos o controlador).') }
    [pscustomobject]@{ PhysicalDisks = $list; FailurePredict = $predict }
}

# ---------- 5. Procesos ----------
$processes = Get-Section 'procesos' {
    $logical = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
    $first = @{}
    foreach ($p in Get-Process) { if ($p.Id -eq 0) { continue }; try { $first[$p.Id] = $p.TotalProcessorTime.TotalSeconds } catch { } }
    Start-Sleep -Seconds $SampleSeconds
    $rows = @(foreach ($p in Get-Process) {
        if ($p.Id -eq 0) { continue }   # 'Idle' no es un proceso real y falsea la CPU
        $delta = 0.0
        try {
            $now = $p.TotalProcessorTime.TotalSeconds
            if ($first.ContainsKey($p.Id)) { $delta = $now - $first[$p.Id] }
        } catch { }
        [pscustomobject]@{
            Name         = $p.ProcessName
            Id           = $p.Id
            CpuPercent   = [math]::Round(100 * $delta / ($SampleSeconds * $logical), 1)
            WorkingSetMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
        }
    })
    $grouped = @($rows | Group-Object Name | ForEach-Object {
        [pscustomobject]@{
            Name         = $_.Name
            Instances    = $_.Count
            CpuPercent   = [math]::Round(($_.Group | Measure-Object CpuPercent -Sum).Sum, 1)
            WorkingSetMB = [math]::Round(($_.Group | Measure-Object WorkingSetMB -Sum).Sum, 1)
        }
    })
    [pscustomobject]@{
        SampleSeconds          = $SampleSeconds
        ProcessCount           = $rows.Count
        TotalCpuPercentSampled = [math]::Round(($rows | Measure-Object CpuPercent -Sum).Sum, 1)
        TopByCpu               = @($grouped | Sort-Object CpuPercent -Descending | Select-Object -First $TopProcesses)
        TopByRam               = @($grouped | Sort-Object WorkingSetMB -Descending | Select-Object -First $TopProcesses)
        AllByName              = @($grouped | Sort-Object WorkingSetMB -Descending)
    }
}

# ---------- 6. Aplicaciones y ultimo uso aproximado ----------
$lastRunByExe = @{}
Get-Section 'ultimo uso (prefetch)' {
    if ($isAdmin -and (Test-Path 'C:\Windows\Prefetch')) {
        Get-ChildItem 'C:\Windows\Prefetch' -Filter '*.pf' -ErrorAction Stop | ForEach-Object {
            $exe = ($_.Name -replace '-[0-9A-F]{8}\.pf$', '').ToLower()
            if (-not $lastRunByExe.ContainsKey($exe) -or $_.LastWriteTimeUtc -gt $lastRunByExe[$exe].When) {
                $lastRunByExe[$exe] = @{ When = $_.LastWriteTimeUtc; Source = 'Prefetch' }
            }
        }
    } elseif (-not $isAdmin) { $notes.Add('Ultimo uso por Prefetch omitido (requiere administrador).') }
} | Out-Null
Get-Section 'ultimo uso (UserAssist)' {
    $ua = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
    foreach ($guid in Get-ChildItem $ua -ErrorAction Stop) {
        $countPath = Join-Path $guid.PSPath 'Count'
        if (-not (Test-Path $countPath)) { continue }
        $key = Get-Item -LiteralPath $countPath
        foreach ($n in $key.GetValueNames()) {
            $b = $key.GetValue($n)
            if ($b -isnot [byte[]] -or $b.Length -lt 68) { continue }
            $ft = [BitConverter]::ToInt64($b, 60)
            if ($ft -le 0) { continue }
            $when = [DateTime]::FromFileTimeUtc($ft)
            $exe = ((ConvertFrom-Rot13 $n) -split '\\')[-1].ToLower()
            if (-not $exe.EndsWith('.exe')) { continue }
            if (-not $lastRunByExe.ContainsKey($exe) -or $when -gt $lastRunByExe[$exe].When) {
                $lastRunByExe[$exe] = @{ When = $when; Source = 'UserAssist' }
            }
        }
    }
} | Out-Null

$apps = Get-Section 'aplicaciones' {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $seen = @{}
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($item in (Get-ItemProperty $paths -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($item.DisplayName)) { continue }
        if ($item.PSObject.Properties['SystemComponent'] -and $item.SystemComponent -eq 1) { continue }
        $key = "$($item.DisplayName)|$($item.DisplayVersion)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $exe = $null
        if ($item.PSObject.Properties['DisplayIcon'] -and $item.DisplayIcon) {
            $icon = ($item.DisplayIcon -replace ',\s*-?\d+$', '').Trim('"')
            if ($icon -match '\.exe$') { $exe = (Split-Path $icon -Leaf).ToLower() }
        }
        $last = $null; $src = 'desconocido'
        if ($exe -and $lastRunByExe.ContainsKey($exe)) {
            $last = $lastRunByExe[$exe].When.ToString('s') + 'Z'; $src = $lastRunByExe[$exe].Source
        }
        $out.Add([pscustomobject]@{
            Name            = $item.DisplayName
            Version         = $item.DisplayVersion
            Publisher       = $item.Publisher
            InstallDate     = $item.InstallDate
            InstallLocation = Hide-UserPath $item.InstallLocation
            Executable      = $exe
            LastUseUtc      = $last
            LastUseSource   = $src
        })
    }
    @($out | Sort-Object Name)
}

# ---------- 7. Navegadores: version ----------
$browserDefs = @(
    @{ Name = 'Chrome';  Exe = 'chrome.exe' },
    @{ Name = 'Edge';    Exe = 'msedge.exe' },
    @{ Name = 'Firefox'; Exe = 'firefox.exe' },
    @{ Name = 'Brave';   Exe = 'brave.exe' },
    @{ Name = 'Opera';   Exe = 'opera.exe' }
)
$browsers = Get-Section 'navegadores' {
    $res = @()
    foreach ($b in $browserDefs) {
        $path = $null
        foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths') {
            $k = Join-Path $root $b.Exe
            if (Test-Path $k) { $v = (Get-ItemProperty $k).'(default)'; if ($v -and (Test-Path $v)) { $path = $v; break } }
        }
        if ($path) {
            $vi = (Get-Item $path).VersionInfo
            $res += [pscustomobject]@{ Browser = $b.Name; Version = $vi.ProductVersion; Path = (Hide-UserPath $path) }
        }
    }
    $res
}

# ---------- 8. "Logs" de navegador: eventos de Windows y reportes de cierre (solo metadatos) ----------
$browserExes = $browserDefs | ForEach-Object { $_.Exe }
$browserEvents = Get-Section 'eventos de navegador' {
    $since = (Get-Date).AddDays(-$EventDays)
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1002; StartTime = $since } -ErrorAction SilentlyContinue |
        Where-Object { $browserExes -contains ([string]$_.Properties[0].Value).ToLower() })
    $rows = @($ev | ForEach-Object {
        [pscustomobject]@{
            TimeUtc    = $_.TimeCreated.ToUniversalTime().ToString('s') + 'Z'
            EventId    = $_.Id
            Kind       = $(if ($_.Id -eq 1000) { 'crash' } else { 'hang' })
            App        = [string]$_.Properties[0].Value
            AppVersion = $(if ($_.Id -eq 1000) { [string]$_.Properties[1].Value } else { $null })
            Module     = $(if ($_.Id -eq 1000) { [string]$_.Properties[3].Value } else { $null })
        }
    })
    [pscustomobject]@{
        Days   = $EventDays
        Count  = $rows.Count
        ByApp  = @($rows | Group-Object App | ForEach-Object { [pscustomobject]@{ App = $_.Name; Count = $_.Count } })
        Events = @($rows | Sort-Object TimeUtc -Descending)
    }
}
$crashDirs = @(
    @{ Browser = 'Chrome';  Path = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Crashpad\reports' },
    @{ Browser = 'Edge';    Path = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Crashpad\reports' },
    @{ Browser = 'Brave';   Path = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data\Crashpad\reports' },
    @{ Browser = 'Firefox'; Path = Join-Path $env:APPDATA 'Mozilla\Firefox\Crash Reports\pending' }
)
$crashReports = Get-Section 'reportes de cierre' {
    @(foreach ($d in $crashDirs) {
        if (Test-Path $d.Path) {
            $files = @(Get-ChildItem $d.Path -File -ErrorAction SilentlyContinue)
            [pscustomobject]@{
                Browser   = $d.Browser
                Files     = $files.Count
                NewestUtc = $(if ($files.Count) { ($files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc.ToString('s') + 'Z' } else { $null })
                OldestUtc = $(if ($files.Count) { ($files | Sort-Object LastWriteTimeUtc | Select-Object -First 1).LastWriteTimeUtc.ToString('s') + 'Z' } else { $null })
                SizeKB    = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1KB, 1)
            }
        }
    })
}

# ---------- 9. Red: adaptadores, WiFi actual y eventos WLAN ----------
$adapters = Get-Section 'adaptadores de red' {
    @(Get-NetAdapter -Physical -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Name          = $_.Name
            Description   = $_.InterfaceDescription
            Status        = $_.Status
            LinkSpeed     = $_.LinkSpeed
            MediaType     = $_.PhysicalMediaType
            DriverVersion = $_.DriverVersionString
            DriverDate    = $(if ($_.DriverDate) { ([datetime]$_.DriverDate).ToString('yyyy-MM-dd') } else { $null })
            DriverProvider = $_.DriverProvider
        }
    })
}
function Get-BandFromText([string]$text, $channel) {
    if ($text -match '(\d(?:\.\d)?)\s*GHz') { return ($Matches[1] + ' GHz') }
    if ($channel) {
        $c = [int]$channel
        if ($c -ge 1 -and $c -le 14) { return '2.4 GHz' }
        if ($c -ge 32 -and $c -le 177) { return '5 GHz' }
    }
    return $null
}
$wifi = Get-Section 'wifi conectado (netsh)' {
    $txt = (& netsh wlan show interfaces 2>&1 | Out-String)
    [System.IO.File]::WriteAllText((Join-Path $runDir 'wlan-interfaces.txt'), $txt, $utf8)
    $ssid = $null; $bssid = $null; $signal = $null; $channel = $null; $radio = $null; $rx = $null; $tx = $null; $auth = $null
    foreach ($line in ($txt -split "`r?`n")) {
        if ($null -eq $ssid -and $line -match '^\s*SSID\s*:\s*(.+?)\s*$') { $ssid = $Matches[1] }
        elseif ($null -eq $bssid -and $line -match '^\s*BSSID\s*:\s*(.+?)\s*$') { $bssid = $Matches[1] }
        elseif ($null -eq $channel -and $line -match '^\s*(Channel|Canal|Kanal|Canale)\s*:\s*(\d+)\s*$') { $channel = [int]$Matches[2] }
        elseif ($null -eq $radio -and $line -match '^\s*(Radio type|Tipo de radio|Funktyp|Type de radio)\s*:\s*(.+?)\s*$') { $radio = $Matches[2] }
        elseif ($null -eq $rx -and $line -match '^\s*(Receive rate|Velocidad de recepci).*:\s*([\d.,]+)\s*$') { $rx = $Matches[2] }
        elseif ($null -eq $tx -and $line -match '^\s*(Transmit rate|Velocidad de transmisi).*:\s*([\d.,]+)\s*$') { $tx = $Matches[2] }
        elseif ($null -eq $auth -and $line -match '^\s*(Authentication|Autenticaci).*:\s*(.+?)\s*$') { $auth = $Matches[2] }
        elseif ($null -eq $signal -and $line -match ':\s*(\d{1,3})\s*%') { $signal = [int]$Matches[1] }
    }
    [pscustomobject]@{
        Ssid = $ssid; Bssid = $bssid; Band = (Get-BandFromText $txt $channel); Channel = $channel; RadioType = $radio
        SignalPercent = $signal; RxMbps = $rx; TxMbps = $tx; Authentication = $auth
    }
}
$wifiSat = Get-Section 'canales WiFi cercanos (netsh)' {
    $txt = (& netsh wlan show networks mode=bssid 2>&1 | Out-String)
    [System.IO.File]::WriteAllText((Join-Path $runDir 'wlan-networks.txt'), $txt, $utf8)
    $aps = New-Object System.Collections.Generic.List[object]
    $cur = $null
    foreach ($line in ($txt -split "`r?`n")) {
        if ($line -match '^\s*BSSID\s+\d+\s*:\s*(.+?)\s*$') {
            if ($cur) { $aps.Add($cur) }
            $cur = @{ Bssid = $Matches[1]; Signal = $null; Channel = $null; Band = $null; Radio = $null }
        } elseif ($cur) {
            if ($line -match '^\s*(Channel|Canal|Kanal|Canale)\s*:\s*(\d+)\s*$') { $cur.Channel = [int]$Matches[2] }
            elseif ($line -match '^\s*(Radio type|Tipo de radio|Funktyp|Type de radio)\s*:\s*(.+?)\s*$') { $cur.Radio = $Matches[2] }
            elseif ($line -match '^\s*(Band|Banda|Frequenzband|Bande)\s*:\s*(.+?)\s*$') { $cur.Band = $Matches[2] }
            elseif ($line -match ':\s*(\d{1,3})\s*%') { $cur.Signal = [int]$Matches[1] }
        }
    }
    if ($cur) { $aps.Add($cur) }
    $myBssid = $(if ($wifi -and $wifi.Bssid) { $wifi.Bssid.ToLower() } else { '' })
    $rows = @($aps | ForEach-Object {
        [pscustomobject]@{
            Band          = (Get-BandFromText ([string]$_.Band) $_.Channel)
            Channel       = $_.Channel
            SignalPercent = $_.Signal
            RadioType     = $_.Radio
            IsConnectedAp = ($myBssid -ne '' -and ([string]$_.Bssid).ToLower() -eq $myBssid)
        }
    })
    $channels = @($rows | Where-Object { $_.Channel } | Group-Object Band, Channel | ForEach-Object {
        $g = $_.Group
        [pscustomobject]@{
            Band = $g[0].Band; Channel = $g[0].Channel; AccessPoints = $g.Count
            MaxSignal = ($g | Measure-Object SignalPercent -Maximum).Maximum
            AvgSignal = [math]::Round(($g | Measure-Object SignalPercent -Average).Average, 0)
        }
    } | Sort-Object Band, Channel)
    $same = @(); $overlap = @(); $least = $null
    if ($wifi -and $wifi.Channel) {
        $others = @($rows | Where-Object { -not $_.IsConnectedAp -and $_.Band -eq $wifi.Band })
        $same = @($others | Where-Object { $_.Channel -eq $wifi.Channel })
        if ($wifi.Band -eq '2.4 GHz') { $overlap = @($others | Where-Object { $_.Channel -ne $wifi.Channel -and [math]::Abs($_.Channel - $wifi.Channel) -le 4 }) }
    }
    $c24 = @($rows | Where-Object { $_.Band -eq '2.4 GHz' -and $_.Channel })
    if ($c24.Count -gt 0) {
        $load = foreach ($ch in 1, 6, 11) { [pscustomobject]@{ Channel = $ch; Count = @($c24 | Where-Object { [math]::Abs($_.Channel - $ch) -le 4 }).Count } }
        $least = ($load | Sort-Object Count, Channel | Select-Object -First 1).Channel
    }
    [pscustomobject]@{
        AccessPointsSeen = $rows.Count
        ConnectedBand = $(if ($wifi) { $wifi.Band } else { $null })
        ConnectedChannel = $(if ($wifi) { $wifi.Channel } else { $null })
        OthersOnSameChannel = $same.Count
        StrongOthersOnSameChannel = @($same | Where-Object { $_.SignalPercent -ge 50 }).Count
        OthersOnOverlappingChannels24 = $(if ($wifi -and $wifi.Band -eq '2.4 GHz') { $overlap.Count } else { $null })
        LeastCongested24Of_1_6_11 = $least
        Channels = $channels
        AccessPoints = $rows
    }
}
if ($wifiSat -and $wifiSat.AccessPointsSeen -gt 0) { $notes.Add('Canales vecinos: lista de redes del ultimo escaneo de Windows (puede estar desactualizada); wlan-networks.txt contiene los nombres de las redes vecinas.') }
$wlan = Get-Section 'eventos WLAN' {
    $since = (Get-Date).AddDays(-$EventDays)
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-WLAN-AutoConfig/Operational'; Id = 8001, 8002, 8003; StartTime = $since } -ErrorAction SilentlyContinue)
    $rows = @($ev | ForEach-Object {
        [pscustomobject]@{
            TimeUtc = $_.TimeCreated.ToUniversalTime().ToString('s') + 'Z'
            EventId = $_.Id
            Kind    = $(switch ($_.Id) { 8001 { 'conectado' } 8002 { 'conexion fallida' } 8003 { 'desconectado' } default { 'otro' } })
        }
    })
    [pscustomobject]@{
        Days         = $EventDays
        Connected    = @($rows | Where-Object { $_.EventId -eq 8001 }).Count
        Failed       = @($rows | Where-Object { $_.EventId -eq 8002 }).Count
        Disconnected = @($rows | Where-Object { $_.EventId -eq 8003 }).Count
        Events       = @($rows | Sort-Object TimeUtc -Descending)
    }
}

# ---------- 8b. Windows Update: ultima busqueda e instalacion exitosas (solo lectura) ----------
$wu = Get-Section 'windows update' {
    $since = (Get-Date).AddDays(-$EventDays)
    function Convert-WuDate($d) {
        if ($null -eq $d) { return $null }
        try { $dt = [datetime]$d; if ($dt.Year -lt 2000) { return $null }; return $dt.ToString('s') + 'Z' } catch { return $null }
    }
    $lastSearch = $null; $lastInstall = $null
    try {
        $au = New-Object -ComObject Microsoft.Update.AutoUpdate
        $lastSearch = Convert-WuDate $au.Results.LastSearchSuccessDate
        $lastInstall = Convert-WuDate $au.Results.LastInstallationSuccessDate
    } catch { $notes.Add('Windows Update: no se pudo leer Microsoft.Update.AutoUpdate (' + $_.Exception.Message + ').') }
    $history = @()
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $total = $searcher.GetTotalHistoryCount()
        $take = [math]::Min($total, 80)
        if ($take -gt 0) {
            $history = @($searcher.QueryHistory(0, $take) | ForEach-Object {
                [pscustomobject]@{
                    TimeUtc   = Convert-WuDate $_.Date
                    Operation = $(switch ([int]$_.Operation) { 1 { 'instalacion' } 2 { 'desinstalacion' } default { 'otra' } })
                    Result    = $(switch ([int]$_.ResultCode) { 2 { 'exitoso' } 3 { 'exitoso con errores' } 4 { 'fallido' } 5 { 'cancelado' } default { 'otro' } })
                    Title     = $_.Title
                }
            })
        }
    } catch { $notes.Add('Windows Update: no se pudo leer el historial (' + $_.Exception.Message + ').') }
    $lastOk = @($history | Where-Object { $_.Operation -eq 'instalacion' -and ($_.Result -eq 'exitoso' -or $_.Result -eq 'exitoso con errores') } | Sort-Object TimeUtc -Descending | Select-Object -First 1)
    $lastOkTime = $(if ($lastOk.Count) { $lastOk[0].TimeUtc } else { $null })
    $failedRecent = @($history | Where-Object { $_.Operation -eq 'instalacion' -and ($_.Result -eq 'fallido' -or $_.Result -eq 'cancelado') -and $_.TimeUtc -and ([datetime]$_.TimeUtc.TrimEnd('Z')) -ge $since.ToUniversalTime() })
    $hotfix = @()
    try { $hotfix = @(Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object -First 15 | ForEach-Object { [pscustomobject]@{ HotFixID = $_.HotFixID; Description = $_.Description; InstalledOn = $(if ($_.InstalledOn) { ([datetime]$_.InstalledOn).ToString('yyyy-MM-dd') } else { $null }) } }) } catch { }
    $pendingReboot = $false
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { if (Test-Path $k) { $pendingReboot = $true } }
    $svc = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $evFail = 0
    try { $evFail = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-WindowsUpdateClient/Operational'; Id = 20, 31; StartTime = $since } -ErrorAction Stop).Count } catch { }
    [pscustomobject]@{
        LastSearchSuccess        = $lastSearch
        LastInstallSuccess       = $lastInstall
        LastSuccessfulInstallHistory = $lastOkTime
        FailedOrCancelledRecent  = $failedRecent.Count
        ClientFailureEvents      = $evFail
        PendingReboot            = $pendingReboot
        ServiceStatus            = $(if ($svc) { [string]$svc.Status } else { $null })
        ServiceStartType         = $(if ($svc) { [string]$svc.StartType } else { $null })
        History                  = @($history | Select-Object -First 30)
        RecentHotFixes           = $hotfix
    }
}

# ---------- 9a. Antivirus (solo lectura; no inicia analisis ni actualiza firmas) ----------
$av = Get-Section 'antivirus' {
    $since = (Get-Date).AddDays(-$EventDays)
    $products = @()
    try {
        $products = @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object {
            $hex = '{0:X6}' -f [int]$_.productState
            [pscustomobject]@{
                Name               = $_.displayName
                ProductStateHex    = $hex
                Enabled            = (@('10', '11') -contains $hex.Substring(2, 2))
                SignaturesUpToDate = ($hex.Substring(4, 2) -eq '00')
            }
        })
    } catch { $notes.Add('SecurityCenter2 no disponible: no se pudo listar los antivirus registrados (Enabled y SignaturesUpToDate salen de decodificar productState y son orientativos).') }
    $def = $null
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $age = { param($v) if ($null -eq $v -or [uint64]$v -ge 4294967295) { $null } else { [int]$v } }
        $def = [pscustomobject]@{
            ServiceEnabled     = $mp.AMServiceEnabled
            AntivirusEnabled   = $mp.AntivirusEnabled
            RealTimeProtection = $mp.RealTimeProtectionEnabled
            BehaviorMonitor    = $mp.BehaviorMonitorEnabled
            TamperProtected    = $mp.IsTamperProtected
            EngineVersion      = $mp.AMEngineVersion
            SignatureVersion   = $mp.AntivirusSignatureVersion
            SignatureAgeDays   = (& $age $mp.AntivirusSignatureAge)
            QuickScanAgeDays   = (& $age $mp.QuickScanAge)
            FullScanAgeDays    = (& $age $mp.FullScanAge)
        }
    } catch { $notes.Add('Get-MpComputerStatus no disponible (Defender no es el antivirus activo, o faltan permisos).') }
    $threats = @()
    try {
        $names = @{}; $sevById = @{}
        $sevName = @{ 0 = 'desconocida'; 1 = 'baja'; 2 = 'moderada'; 4 = 'alta'; 5 = 'grave' }
        foreach ($t in @(Get-MpThreat -ErrorAction SilentlyContinue)) { $names[[string]$t.ThreatID] = $t.ThreatName; $sevById[[string]$t.ThreatID] = $t.SeverityID }
        $threats = @(Get-MpThreatDetection -ErrorAction Stop | Where-Object { $_.InitialDetectionTime -ge $since } |
            Sort-Object InitialDetectionTime -Descending | Select-Object -First 50 | ForEach-Object {
            $res = (@($_.Resources) -join '; ')
            if ($res.Length -gt 200) { $res = $res.Substring(0, 200) + '...' }
            [pscustomobject]@{
                TimeUtc       = $_.InitialDetectionTime.ToUniversalTime().ToString('s') + 'Z'
                ThreatName    = $names[[string]$_.ThreatID]
                Severity      = $(if ($sevById.ContainsKey([string]$_.ThreatID)) { $sevName[[int]$sevById[[string]$_.ThreatID]] } else { $null })
                ThreatId      = $_.ThreatID
                ProcessName   = $_.ProcessName
                ActionSuccess = $_.ActionSuccess
                Resources     = (Hide-UserPath $res)
            }
        })
    } catch { $notes.Add('Get-MpThreatDetection no disponible (Defender no activo o faltan permisos).') }
    $kinds = @{ 1116 = 'amenaza detectada'; 1117 = 'accion tomada'; 1118 = 'accion fallida'; 1119 = 'error critico en la accion'; 3002 = 'falla de la proteccion en tiempo real'; 5001 = 'proteccion en tiempo real deshabilitada'; 5007 = 'cambio de configuracion' }
    $dev = @()
    try {
        $dev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1116, 1117, 1118, 1119, 3002, 5001, 5007; StartTime = $since } -ErrorAction Stop |
            Select-Object -First 100 | ForEach-Object {
            [pscustomobject]@{ TimeUtc = $_.TimeCreated.ToUniversalTime().ToString('s') + 'Z'; EventId = $_.Id; Kind = $kinds[[int]$_.Id] }
        })
    } catch { if ($_.Exception.Message -notmatch 'No events|No se encontraron') { $notes.Add('Eventos de Defender no disponibles: ' + $_.Exception.Message) } }
    # Procesos del antivirus (de la muestra de procesos): consumo de CPU y RAM
    $avProcNames = @('MsMpEng', 'MpDefenderCoreService', 'NisSrv', 'SecurityHealthService', 'SenseIR', 'MsSense', 'mcshield', 'masvc', 'ekrn', 'avp', 'bdservicehost', 'SentinelAgent', 'CylanceSvc', 'CSFalconService', 'savservice', 'SophosHealth', 'wsc_proxy')
    $avProcs = @()
    if ($processes) { $avProcs = @($processes.AllByName | Where-Object { $avProcNames -contains $_.Name }) }
    [pscustomobject]@{ Days = $EventDays; Products = $products; Defender = $def; Threats = $threats; DefenderEvents = $dev; AvProcesses = $avProcs }
}

# ---------- 9b. Visor de eventos: errores y advertencias recientes, e indicadores de caidas ----------
$eventViewer = Get-Section 'visor de eventos (System/Application)' {
    $since = (Get-Date).AddDays(-$EventDays)
    $all = @(Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 1, 2, 3; StartTime = $since } -MaxEvents $MaxEventsRead -ErrorAction SilentlyContinue)
    $kind = @{ 1 = 'critico'; 2 = 'error'; 3 = 'advertencia' }
    $crashMap = @{
        'Microsoft-Windows-Kernel-Power'             = @(41)
        'EventLog'                                   = @(6008)
        'Microsoft-Windows-WER-SystemErrorReporting' = @(1001)
        'Application Error'                          = @(1000)
        'Application Hang'                           = @(1002)
        'Microsoft-Windows-WHEA-Logger'              = @(1, 17, 18, 19, 20)
        'Display'                                    = @(4101)
        'disk'                                       = @(7, 11, 51, 153)
        'Ntfs'                                       = @(55, 98, 137)
    }
    function Test-CrashEvent($e) { return ($crashMap.ContainsKey($e.ProviderName) -and ($crashMap[$e.ProviderName] -contains [int]$e.Id)) }
    $summary = @($all | Group-Object { '{0}|{1}|{2}|{3}' -f $_.LogName, $_.ProviderName, $_.Id, $_.Level } | ForEach-Object {
        $f = $_.Group[0]
        $times = @($_.Group | ForEach-Object { $_.TimeCreated } | Sort-Object)
        [pscustomobject]@{
            Log = $f.LogName; Provider = $f.ProviderName; EventId = $f.Id; Level = $kind[[int]$f.Level]; Count = $_.Count
            FirstUtc = $times[0].ToUniversalTime().ToString('s') + 'Z'; LastUtc = $times[-1].ToUniversalTime().ToString('s') + 'Z'
        }
    } | Sort-Object Count -Descending | Select-Object -First 40)
    $recent = @($all | Select-Object -First 40 | ForEach-Object {
        [pscustomobject]@{ TimeUtc = $_.TimeCreated.ToUniversalTime().ToString('s') + 'Z'; Log = $_.LogName; Level = $kind[[int]$_.Level]; Provider = $_.ProviderName; EventId = $_.Id }
    })
    $crashAll = @($all | Where-Object { Test-CrashEvent $_ })
    $crashSummary = @($crashAll | Group-Object { '{0}|{1}' -f $_.ProviderName, $_.Id } | ForEach-Object {
        [pscustomobject]@{ Provider = $_.Group[0].ProviderName; EventId = $_.Group[0].Id; Count = $_.Count; LastUtc = (($_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated.ToUniversalTime().ToString('s') + 'Z') }
    } | Sort-Object Count -Descending)
    $crashRecent = @($crashAll | Select-Object -First 30 | ForEach-Object {
        $m = ''
        try { $m = ([string]$_.Message -replace '\s+', ' ').Trim(); if ($m.Length -gt 200) { $m = $m.Substring(0, 200) + '...' }; $m = Hide-UserPath $m } catch { }
        [pscustomobject]@{ TimeUtc = $_.TimeCreated.ToUniversalTime().ToString('s') + 'Z'; Log = $_.LogName; Provider = $_.ProviderName; EventId = $_.Id; Message = $m }
    })
    [pscustomobject]@{
        Days = $EventDays; Read = $all.Count; MaxEventsRead = $MaxEventsRead; Truncated = ($all.Count -ge $MaxEventsRead)
        Critical = @($all | Where-Object { $_.Level -eq 1 }).Count
        Errors = @($all | Where-Object { $_.Level -eq 2 }).Count
        Warnings = @($all | Where-Object { $_.Level -eq 3 }).Count
        CrashIndicators = $crashAll.Count
        Summary = $summary; Recent = $recent; CrashSummary = $crashSummary; Crashes = $crashRecent
    }
}
if ($eventViewer -and $eventViewer.Truncated) { $notes.Add("Visor de eventos: se leyeron los ultimos $MaxEventsRead eventos; puede haber mas en los $EventDays dias (usar -MaxEventsRead).") }

# ---------- 10. Gateway y prueba de ping / jitter ----------
function Get-RttStats($rtts, [int]$sent) {
    $vals = @($rtts | ForEach-Object { [double]$_ })
    $n = [int]$vals.Count
    $min = $null; $max = $null; $avg = $null; $p95 = $null; $std = $null; $jit = $null
    if ($n -gt 0) {
        $sum = 0.0; $lo = $vals[0]; $hi = $vals[0]
        foreach ($v in $vals) { $sum += $v; if ($v -lt $lo) { $lo = $v }; if ($v -gt $hi) { $hi = $v } }
        $mean = $sum / $n
        $min = [math]::Round([double]$lo, 2); $max = [math]::Round([double]$hi, 2); $avg = [math]::Round([double]$mean, 2)
        $sorted = @($vals | Sort-Object)
        $idx = [int][math]::Ceiling([double](0.95 * $n)) - 1
        if ($idx -lt 0) { $idx = 0 }
        if ($idx -gt ($n - 1)) { $idx = $n - 1 }
        $p95 = [math]::Round([double]$sorted[$idx], 2)
        $var = 0.0
        foreach ($v in $vals) { $var += ($v - $mean) * ($v - $mean) }
        $std = [math]::Round([double][math]::Sqrt($var / $n), 2)
    }
    if ($n -gt 1) {
        $acc = 0.0
        for ($k = 1; $k -lt $n; $k++) { $acc += [math]::Abs($vals[$k] - $vals[$k - 1]) }
        $jit = [math]::Round([double]($acc / ($n - 1)), 2)
    }
    $den = [double]([math]::Max($sent, 1))
    return @{
        Sent = $sent; Received = $n
        LossPercent = [math]::Round([double](100.0 * ($sent - $n) / $den), 1)
        MinMs = $min; AvgMs = $avg; P95Ms = $p95; MaxMs = $max; StdDevMs = $std; JitterMs = $jit
        SamplesMs = (($vals | ForEach-Object { [math]::Round($_, 2) }) -join ',')
    }
}
function Test-PingStats([string]$Target, [int]$Count, [int]$IntervalMs, [string]$Role = '') {
    $p = New-Object System.Net.NetworkInformation.Ping
    $rtts = New-Object System.Collections.Generic.List[double]
    for ($i = 0; $i -lt $Count; $i++) {
        try {
            $r = $p.Send($Target, 1000)
            if ($r.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { $rtts.Add([double]$r.RoundtripTime) }
        } catch { }
        if ($i -lt $Count - 1) { Start-Sleep -Milliseconds $IntervalMs }
    }
    $st = Get-RttStats $rtts $Count
    [pscustomobject]@{
        Role = $Role; Target = $Target; Sent = $st.Sent; Received = $st.Received; LossPercent = $st.LossPercent
        MinMs = $st.MinMs; AvgMs = $st.AvgMs; P95Ms = $st.P95Ms; MaxMs = $st.MaxMs; StdDevMs = $st.StdDevMs; JitterMs = $st.JitterMs
        SamplesMs = $st.SamplesMs
    }
}
function Test-HttpLatency([string]$Url, [int]$Count, [int]$IntervalMs, [string]$Role = '') {
    Add-Type -AssemblyName System.Net.Http
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(5)
    $rtts = New-Object System.Collections.Generic.List[double]
    $first = $null
    # la peticion 0 es de calentamiento (DNS + TCP + TLS) y no entra en las estadisticas; las demas reutilizan la conexion
    for ($i = 0; $i -le $Count; $i++) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            $resp = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            $null = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            $sw.Stop()
            if ($i -eq 0) { $first = [math]::Round($sw.Elapsed.TotalMilliseconds, 1) }
            elseif ($resp.IsSuccessStatusCode) { $rtts.Add($sw.Elapsed.TotalMilliseconds) }
            $resp.Dispose()
        } catch { }
        if ($i -lt $Count) { Start-Sleep -Milliseconds $IntervalMs }
    }
    $client.Dispose()
    $st = Get-RttStats $rtts $Count
    [pscustomobject]@{
        Role = $Role; Target = $Url; Sent = $st.Sent; Received = $st.Received; LossPercent = $st.LossPercent
        MinMs = $st.MinMs; AvgMs = $st.AvgMs; P95Ms = $st.P95Ms; MaxMs = $st.MaxMs; StdDevMs = $st.StdDevMs; JitterMs = $st.JitterMs
        SamplesMs = $st.SamplesMs; FirstRequestMs = $first
    }
}
$gateway = Get-Section 'gateway' {
    $r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
    if (-not $r) { return $null }
    $ad = Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Address     = [string]$r.NextHop
        Interface   = $r.InterfaceAlias
        Description = $(if ($ad) { $ad.InterfaceDescription } else { $null })
        MediaType   = $(if ($ad) { $ad.PhysicalMediaType } else { $null })
    }
}
$netExtra = Get-Section 'rutas, proxy y VPN' {
    $ifIdx = @{}
    foreach ($ni in @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue)) { $ifIdx[[int]$ni.InterfaceIndex] = $ni }
    $adIdx = @{}
    foreach ($ad2 in @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue)) { $adIdx[[int]$ad2.ifIndex] = $ad2 }
    $routes = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop | Where-Object {
            $_.DestinationPrefix -notlike '224.*' -and $_.DestinationPrefix -notlike '127.*' -and
            $_.DestinationPrefix -ne '255.255.255.255/32' -and $_.DestinationPrefix -notlike '169.254.*' } | ForEach-Object {
            $ni = $ifIdx[[int]$_.InterfaceIndex]; $ad2 = $adIdx[[int]$_.InterfaceIndex]
            [pscustomobject]@{
                Destination = $_.DestinationPrefix; NextHop = [string]$_.NextHop; Interface = $_.InterfaceAlias
                AdapterStatus = $(if ($ad2) { [string]$ad2.Status } else { $null })
                RouteMetric = $_.RouteMetric; InterfaceMetric = $(if ($ni) { $ni.InterfaceMetric } else { $null })
                Protocol = [string]$_.Protocol; Store = [string]$_.Store
            } } | Sort-Object Destination, RouteMetric)
    $ipIf = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{ Interface = $_.InterfaceAlias; ConnectionState = [string]$_.ConnectionState; InterfaceMetric = $_.InterfaceMetric; AutomaticMetric = [string]$_.AutomaticMetric; Dhcp = [string]$_.Dhcp } })
    $vpn = New-Object System.Collections.Generic.List[object]
    foreach ($allUsers in @($true, $false)) {
        try {
            foreach ($v in @(Get-VpnConnection -AllUserConnection:$allUsers -ErrorAction Stop)) {
                $vpn.Add([pscustomobject]@{ Name = $v.Name; Scope = $(if ($allUsers) { 'all users' } else { 'current user' }); Server = $v.ServerAddress; Status = [string]$v.ConnectionStatus; TunnelType = [string]$v.TunnelType; SplitTunneling = [string]$v.SplitTunneling })
            }
        } catch { }
    }
    $proxy = $null
    try {
        $reg = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        $proxy = [pscustomobject]@{ ProxyEnable = $reg.ProxyEnable; ProxyServer = $reg.ProxyServer; AutoConfigURL = $reg.AutoConfigURL; AutoDetect = $reg.AutoDetect }
    } catch { }
    $winhttp = ''
    try { $winhttp = ((& netsh winhttp show proxy 2>&1 | Out-String).Trim()) } catch { }
    [System.IO.File]::WriteAllText((Join-Path $runDir 'proxy-winhttp.txt'), $winhttp, $utf8)
    [pscustomobject]@{ Routes = $routes; IpInterfaces = $ipIf; Vpn = @($vpn.ToArray()); Proxy = $proxy; WinHttpProxy = $winhttp }
}
$pingResults = Get-Section 'ping y jitter' {
    $out = New-Object System.Collections.Generic.List[object]
    if ($gateway -and $gateway.Address) {
        try { $out.Add((Test-PingStats ([string]$gateway.Address) $PingCount $PingIntervalMs 'gateway')) }
        catch { Write-Failure 'ping al gateway' $_; $notes.Add('Ping al gateway fallo: ' + $_.Exception.Message) }
    } else { $notes.Add('No se encontro gateway predeterminado: sin prueba de ping al gateway.') }
    if (-not $SkipInternet) {
        foreach ($t in $PingTargets) {
            if (-not $t) { continue }
            $role = 'extra'
            if ($t -eq '1.1.1.1' -or $t -eq '1.0.0.1') { $role = 'internet (Cloudflare)' }
            try { $out.Add((Test-PingStats ([string]$t) $PingCount $PingIntervalMs $role)) }
            catch { Write-Failure ("ping a {0}" -f $t) $_; $notes.Add(("Ping a {0} fallo: {1}" -f $t, $_.Exception.Message)) }
        }
        if ($HttpJitterCount -gt 0) {
            try { $out.Add((Test-HttpLatency $CloudflareUrl $HttpJitterCount $PingIntervalMs 'internet-http (Cloudflare)')) }
            catch { Write-Failure 'prueba HTTPS a Cloudflare' $_; $notes.Add('Prueba HTTPS a Cloudflare fallo: ' + $_.Exception.Message) }
        }
    }
    return @($out.ToArray())
}
if ($wifi -and -not $wifi.Ssid) { $notes.Add('SSID no disponible: ver wlan-interfaces.txt (sin WiFi conectado, o Windows 11 reciente sin permiso de ubicacion para netsh).') }

# ---------- CSV ----------
Export-Table $apps 'apps.csv'
if ($processes) { Export-Table $processes.AllByName 'processes-by-name.csv' }
if ($memory) { Export-Table $memory.Modules 'ram-modules.csv' }
if ($disks) { Export-Table $disks.PhysicalDisks 'disks.csv'; Export-Table $disks.FailurePredict 'disks-failure-predict.csv' }
Export-Table $adapters 'network-adapters.csv'
if ($browsers) { Export-Table $browsers 'browsers.csv' }
if ($browserEvents) { Export-Table $browserEvents.Events 'browser-events.csv' }
Export-Table $crashReports 'browser-crash-reports.csv'
if ($wlan) { Export-Table $wlan.Events 'wlan-events.csv' }
if ($wu) { Export-Table $wu.History 'windows-update-history.csv'; Export-Table $wu.RecentHotFixes 'windows-update-hotfixes.csv' }
if ($av) { Export-Table $av.Products 'av-products.csv'; Export-Table $av.Defender 'defender-status.csv'; Export-Table $av.Threats 'defender-threats.csv'; Export-Table $av.AvProcesses 'av-processes.csv'; Export-Table $av.DefenderEvents 'defender-events.csv' }
if ($eventViewer) { Export-Table $eventViewer.Summary 'events-summary.csv'; Export-Table $eventViewer.Recent 'events-recent.csv'; Export-Table $eventViewer.CrashSummary 'events-crash-summary.csv'; Export-Table $eventViewer.Crashes 'events-crashes.csv' }
Export-Table $pingResults 'ping-results.csv'
Export-Table $wifi 'wifi-connected.csv'
if ($wifiSat) { Export-Table $wifiSat.Channels 'wifi-channels.csv'; Export-Table $wifiSat.AccessPoints 'wifi-access-points.csv' }
if ($netExtra) { Export-Table $netExtra.Routes 'routes.csv'; Export-Table $netExtra.IpInterfaces 'ip-interfaces.csv'; Export-Table $netExtra.Vpn 'vpn-connections.csv'; Export-Table @($netExtra.Proxy) 'proxy.csv' }

# ---------- Observaciones (reglas simples; son avisos para mirar, no diagnosticos) ----------
$flags = New-Object System.Collections.Generic.List[object]
function Add-Flag([string]$level, [string]$text) { $flags.Add([pscustomobject]@{ Level = $level; Text = (Add-Accents $text) }) }
if ($memory) {
    $freePct = 100 * $memory.AvailableGB / [math]::Max($memory.TotalGB, 0.01)
    if ($freePct -lt 15) { Add-Flag 'warn' ("RAM disponible baja: {0} GB de {1} GB ({2:N0} %)." -f $memory.AvailableGB, $memory.TotalGB, $freePct) }
    if ($memory.ModuleCount -eq 1) { Add-Flag 'info' 'Un solo m~o~dulo de RAM (posible canal unico).' }
    $speeds = @($memory.Modules | Where-Object { $_.ConfiguredSpeedMHz -and $_.SpeedMHz -and $_.ConfiguredSpeedMHz -lt $_.SpeedMHz })
    if ($speeds.Count -gt 0) { Add-Flag 'info' 'Algun m~o~dulo de RAM funciona a una velocidad menor que la nominal.' }
}
if ($disks) {
    foreach ($d in $disks.PhysicalDisks) {
        if ($d.HealthStatus -and $d.HealthStatus -ne 'Healthy') { Add-Flag 'bad' ("Disco '{0}': salud {1}." -f $d.Name, $d.HealthStatus) }
        if ($d.WearPercent -ne $null -and $d.WearPercent -ge 80) { Add-Flag 'warn' ("Disco '{0}': desgaste {1} %." -f $d.Name, $d.WearPercent) }
        if ($d.TemperatureC -ne $null -and $d.TemperatureC -ge 70) { Add-Flag 'warn' ("Disco '{0}': temperatura {1} C." -f $d.Name, $d.TemperatureC) }
    }
    foreach ($f in $disks.FailurePredict) { if ($f.PredictFailure) { Add-Flag 'bad' 'Windows informa predicci~o~n de falla (SMART) en un disco.' } }
}
if ($processes) {
    $hot = @($processes.TopByCpu | Where-Object { $_.CpuPercent -ge 25 })
    if ($hot.Count -gt 0) { Add-Flag 'warn' ("Procesos con CPU alta en la muestra de {0} s: {1}." -f $processes.SampleSeconds, (($hot | ForEach-Object { "$($_.Name) $($_.CpuPercent) %" }) -join ', ')) }
}
if ($browserEvents -and $browserEvents.Count -gt 0) { Add-Flag 'warn' ("{0} cierres/cuelgues de navegador en los ~u~ltimos {1} d~i~as." -f $browserEvents.Count, $EventDays) }
if ($netExtra) {
    $badDef = @($netExtra.Routes | Where-Object { $_.Destination -eq '0.0.0.0/0' -and $_.AdapterStatus -and $_.AdapterStatus -ne 'Up' })
    if ($badDef.Count -gt 0) { Add-Flag 'warn' ("Ruta predeterminada sobre un adaptador que no esta conectado: {0}." -f (($badDef | ForEach-Object { "$($_.Interface) via $($_.NextHop)" }) -join ', ')) }
    $defCount = @($netExtra.Routes | Where-Object { $_.Destination -eq '0.0.0.0/0' }).Count
    if ($defCount -gt 1) { Add-Flag 'info' ("Hay {0} rutas predeterminadas (ver routes.csv): decide la de menor metrica sumada." -f $defCount) }
    $vpnUp = @($netExtra.Vpn | Where-Object { $_.Status -eq 'Connected' })
    if ($vpnUp.Count -gt 0) { Add-Flag 'warn' ("VPN conectada: {0}." -f (($vpnUp | ForEach-Object { $_.Name }) -join ', ')) }
    elseif (@($netExtra.Vpn).Count -gt 0) { Add-Flag 'info' ("Perfiles de VPN de Windows definidos pero desconectados: {0}." -f (($netExtra.Vpn | ForEach-Object { $_.Name }) -join ', ')) }
    if ($netExtra.Proxy -and $netExtra.Proxy.ProxyEnable -eq 1) { Add-Flag 'info' 'Proxy de usuario activo en Internet Settings (ver proxy.csv).' }
    if ($netExtra.Proxy -and $netExtra.Proxy.AutoConfigURL) { Add-Flag 'info' 'Hay un script de configuracion automatica de proxy (PAC) en Internet Settings (ver proxy.csv).' }
    if ($netExtra.WinHttpProxy -and $netExtra.WinHttpProxy -notmatch '(?i)direct|directo|acceso directo') { Add-Flag 'info' 'WinHTTP tiene un proxy distinto de acceso directo (ver proxy-winhttp.txt).' }
}
if ($wlan -and ($wlan.Disconnected + $wlan.Failed) -gt 0) { Add-Flag 'info' ("WiFi en los ~u~ltimos {0} d~i~as: {1} conexi~o~nes, {2} desconexi~o~nes, {3} conexi~o~nes fallidas." -f $EventDays, $wlan.Connected, $wlan.Disconnected, $wlan.Failed) }
if ($wu) {
    $nowUtc = (Get-Date).ToUniversalTime()
    $inst = $(if ($wu.LastInstallSuccess) { $wu.LastInstallSuccess } else { $wu.LastSuccessfulInstallHistory })
    if ($inst) {
        $days = [math]::Round(($nowUtc - ([datetime]$inst.TrimEnd('Z'))).TotalDays, 0)
        if ($days -gt 45) { Add-Flag 'warn' ("Windows Update: ~u~ltima instalaci~o~n exitosa hace {0} d~i~as." -f $days) }
    } else { Add-Flag 'warn' 'Windows Update: sin registro de instalaci~o~nes exitosas.' }
    if ($wu.LastSearchSuccess) {
        $sd = [math]::Round(($nowUtc - ([datetime]$wu.LastSearchSuccess.TrimEnd('Z'))).TotalDays, 0)
        if ($sd -gt 14) { Add-Flag 'warn' ("Windows Update: ~u~ltima b~u~squeda exitosa hace {0} d~i~as." -f $sd) }
    }
    if ($wu.FailedOrCancelledRecent -gt 0) { Add-Flag 'warn' ("Windows Update: {0} instalaci~o~nes fallidas o canceladas en los ~u~ltimos {1} d~i~as." -f $wu.FailedOrCancelledRecent, $EventDays) }
    if ($wu.PendingReboot) { Add-Flag 'info' 'Windows Update: hay un reinicio pendiente.' }
    if ($wu.ServiceStartType -eq 'Disabled') { Add-Flag 'warn' 'Windows Update: el servicio wuauserv esta deshabilitado.' }
}
if ($av) {
    $enabledProducts = @($av.Products | Where-Object { $_.Enabled })
    if (@($av.Products).Count -gt 0 -and $enabledProducts.Count -eq 0) { Add-Flag 'bad' 'Antivirus: ning~u~n producto registrado figura como activo en el Centro de seguridad de Windows.' }
    if (@($av.Products).Count -eq 0 -and -not $av.Defender) { Add-Flag 'info' 'Antivirus: no se pudo determinar el estado (sin datos del Centro de seguridad ni de Defender).' }
    foreach ($pr2 in @($av.Products | Where-Object { $_.Enabled -and -not $_.SignaturesUpToDate })) { Add-Flag 'warn' ("Antivirus '{0}': firmas desactualizadas seg~u~n el Centro de seguridad." -f $pr2.Name) }
    if ($av.Defender) {
        $d = $av.Defender
        if ($d.RealTimeProtection -eq $false -and $enabledProducts.Count -eq 0) { Add-Flag 'bad' 'Defender: protecci~o~n en tiempo real desactivada y sin otro antivirus activo.' }
        elseif ($d.RealTimeProtection -eq $false) { Add-Flag 'info' 'Defender: protecci~o~n en tiempo real desactivada (puede estar en modo pasivo por otro antivirus).' }
        if ($d.SignatureAgeDays -ne $null -and $d.SignatureAgeDays -gt 7) { Add-Flag 'warn' ("Defender: firmas de hace {0} d~i~as." -f $d.SignatureAgeDays) }
        if ($d.FullScanAgeDays -eq $null -and $d.QuickScanAgeDays -eq $null) { Add-Flag 'info' 'Defender: sin registro de an~a~lisis r~a~pido ni completo.' }
        elseif ($d.QuickScanAgeDays -ne $null -and $d.QuickScanAgeDays -gt 14) { Add-Flag 'info' ("Defender: ~u~ltimo an~a~lisis r~a~pido hace {0} d~i~as." -f $d.QuickScanAgeDays) }
    }
    $thr = @($av.Threats | Where-Object { $null -ne $_ })
    if ($thr.Count -gt 0) { Add-Flag 'bad' ("Defender: {0} detecciones de amenazas en los ~u~ltimos {1} d~i~as ({2} con acci~o~n no exitosa)." -f $thr.Count, $EventDays, @($thr | Where-Object { $_.ActionSuccess -eq $false }).Count) }
    $hi = @($thr | Where-Object { @('alta', 'grave') -contains $_.Severity })
    if ($hi.Count -gt 0) { Add-Flag 'bad' ("Defender: {0} detecciones de severidad alta o grave en los ~u~ltimos {1} d~i~as ({2})." -f $hi.Count, $EventDays, ((@($hi | Select-Object -First 3) | ForEach-Object { $_.ThreatName }) -join ', ')) }
    foreach ($ap in @($av.AvProcesses | Where-Object { $_.CpuPercent -ge 10 })) { Add-Flag 'warn' ("Proceso del antivirus con CPU alta en la muestra: {0} {1} % (RAM {2} MB)." -f $ap.Name, $ap.CpuPercent, $ap.WorkingSetMB) }
    $badEv = @($av.DefenderEvents | Where-Object { @(1118, 1119, 3002, 5001) -contains $_.EventId })
    if ($badEv.Count -gt 0) { Add-Flag 'warn' ("Defender: {0} eventos de falla o de protecci~o~n deshabilitada en los ~u~ltimos {1} d~i~as." -f $badEv.Count, $EventDays) }
}
if ($eventViewer -and $eventViewer.CrashIndicators -gt 0) {
    Add-Flag 'warn' ("Visor de eventos: {0} indicadores de ca~i~da o cierre inesperado en los ~u~ltimos {1} d~i~as ({2})." -f $eventViewer.CrashIndicators, $EventDays, ((@($eventViewer.CrashSummary | Select-Object -First 4) | ForEach-Object { "$($_.Provider) $($_.EventId) x$($_.Count)" }) -join ', '))
}
if ($eventViewer -and $eventViewer.Critical -gt 0) { Add-Flag 'warn' ("Visor de eventos: {0} eventos cr~i~ticos en los ~u~ltimos {1} d~i~as." -f $eventViewer.Critical, $EventDays) }
foreach ($pr in @($pingResults | Where-Object { $null -ne $_ })) {
    $isGw = ($pr.Role -eq 'gateway')
    $label = $(if ($isGw) { "al gateway {0}" -f $pr.Target } else { "a {0} ({1})" -f $pr.Role, $pr.Target })
    if ($pr.Received -eq 0) {
        if ($isGw) { Add-Flag 'bad' ("Sin respuesta de ping del gateway {0} (puede que el gateway no responda ICMP)." -f $pr.Target) }
        else { Add-Flag 'warn' ("Sin respuesta {0} (puede estar bloqueado por la red o el firewall)." -f $label) }
        continue
    }
    $maxAvg = $(if ($isGw) { 20 } else { 100 }); $maxJit = $(if ($isGw) { 10 } else { 30 })
    if ($pr.LossPercent -gt 0) { Add-Flag 'warn' ("Perdida de paquetes {0}: {1} % ({2} de {3})." -f $label, $pr.LossPercent, ($pr.Sent - $pr.Received), $pr.Sent) }
    if ($pr.AvgMs -gt $maxAvg) { Add-Flag 'warn' ("Latencia media {0} alta: {1} ms." -f $label, $pr.AvgMs) }
    if ($pr.JitterMs -gt $maxJit) { Add-Flag 'warn' ("Jitter {0} alto: {1} ms." -f $label, $pr.JitterMs) }
}
$gwRow = @($pingResults | Where-Object { $_.Role -eq 'gateway' }) | Select-Object -First 1
$inetRows = @($pingResults | Where-Object { $_.Role -like 'internet*' -and $_.Received -gt 0 })
if ($gwRow -and $gwRow.Received -gt 0 -and $gwRow.LossPercent -eq 0 -and $gwRow.JitterMs -le 10 -and $inetRows.Count -gt 0 -and @($inetRows | Where-Object { $_.LossPercent -gt 0 -or $_.JitterMs -gt 30 }).Count -gt 0) {
    Add-Flag 'info' 'El gateway responde bien y las pruebas a internet no: sugiere que el problema esta despues del gateway (red de la oficina hacia el proveedor); no esta probado.'
}
if ($wifi -and $wifi.SignalPercent -ne $null -and $wifi.SignalPercent -lt 50) { Add-Flag 'warn' ("Se~n~al WiFi baja: {0} %." -f $wifi.SignalPercent) }
if ($flags.Count -eq 0) { Add-Flag 'info' 'Sin avisos seg~u~n las reglas simples del script.' }

# ---------- JSON ----------
$reportData = New-Object System.Collections.Specialized.OrderedDictionary
function Set-ReportPart([string]$Key, $Value) {
    try { $reportData[$Key] = $Value } catch { Write-Failure ("reporte, clave {0}" -f $Key) $_ }
}
Set-ReportPart 'Tool' 'audit-laptop.ps1 (GITIN-2270)'
Set-ReportPart 'Hostname' $hostName
Set-ReportPart 'GeneratedUtc' ($startUtc.ToString('s') + 'Z')
Set-ReportPart 'RanAsAdministrator' $isAdmin
Set-ReportPart 'System' $system
Set-ReportPart 'Cpu' $cpu
Set-ReportPart 'Memory' $memory
Set-ReportPart 'Disks' $disks
Set-ReportPart 'Processes' $processes
Set-ReportPart 'InstalledApps' $apps
Set-ReportPart 'Browsers' $browsers
Set-ReportPart 'BrowserEvents' $browserEvents
Set-ReportPart 'BrowserCrashReports' $crashReports
Set-ReportPart 'NetworkAdapters' $adapters
Set-ReportPart 'WlanEvents' $wlan
Set-ReportPart 'WindowsUpdate' $wu
Set-ReportPart 'Antivirus' $av
Set-ReportPart 'EventViewer' $eventViewer
Set-ReportPart 'WifiConnected' $wifi
Set-ReportPart 'WifiChannels' $wifiSat
Set-ReportPart 'Gateway' $gateway
Set-ReportPart 'RoutesProxyVpn' $netExtra
Set-ReportPart 'PingToGateway' $pingResults
Set-ReportPart 'Flags' $flags.ToArray()
Set-ReportPart 'Notes' $notes.ToArray()
# JSON clave por clave: si una clave no se puede serializar queda registrada en run.log y el resto se guarda igual
$jsonParts = New-Object System.Collections.Generic.List[string]
foreach ($k in @($reportData.Keys)) {
    try { $jsonParts.Add(('"{0}": {1}' -f $k, (ConvertTo-Json -InputObject $reportData[$k] -Depth 8))) }
    catch { Write-Failure ("json, clave {0}" -f $k) $_; $jsonParts.Add(('"{0}": "error al serializar"' -f $k)) }
}
[System.IO.File]::WriteAllText((Join-Path $runDir 'report.json'), ("{`n" + ($jsonParts -join ",`n") + "`n}"), $utf8)

# ---------- HTML ----------
function HtmlEnc($v) { if ($null -eq $v) { return '' } return [System.Net.WebUtility]::HtmlEncode([string]$v) }
function ConvertTo-HtmlTable($rows, [string[]]$cols) {
    $rows = @($rows | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) { return '<p class="muted">Sin datos.</p>' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<table><thead><tr>')
    foreach ($c in $cols) { [void]$sb.Append('<th>' + (HtmlEnc $c) + '</th>') }
    [void]$sb.Append('</tr></thead><tbody>')
    foreach ($r in $rows) {
        [void]$sb.Append('<tr>')
        foreach ($c in $cols) { [void]$sb.Append('<td>' + (HtmlEnc $r.$c) + '</td>') }
        [void]$sb.Append('</tr>')
    }
    [void]$sb.Append('</tbody></table>')
    return $sb.ToString()
}
function Section([string]$title, [string]$body) { return "<section><h2>$(HtmlEnc $title)</h2>$body</section>" }

$h = New-Object System.Text.StringBuilder
[void]$h.Append('<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">')
[void]$h.Append("<title>Auditor&iacute;a $(HtmlEnc $hostName)</title>")
[void]$h.Append('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#1b1f23;background:#fff}h1{margin:0 0 4px}h2{border-bottom:1px solid #d0d7de;padding-bottom:4px;margin-top:28px}.muted{color:#57606a}table{border-collapse:collapse;width:100%;font-size:13px;margin:8px 0}th,td{border:1px solid #d0d7de;padding:4px 8px;text-align:left;vertical-align:top}th{background:#f6f8fa}.cards{display:flex;flex-wrap:wrap;gap:12px}.card{border:1px solid #d0d7de;border-radius:6px;padding:10px 14px;min-width:200px}.card b{display:block;font-size:12px;color:#57606a;text-transform:uppercase}.flag{padding:6px 10px;border-radius:4px;margin:4px 0}.bad{background:#ffebe9;border:1px solid #ff8182}.warn{background:#fff8c5;border:1px solid #d4a72c}.info{background:#ddf4ff;border:1px solid #54aeff}@media (prefers-color-scheme:dark){body{background:#0d1117;color:#e6edf3}th{background:#161b22}th,td,.card,h2{border-color:#30363d}.muted,.card b{color:#8b949e}.bad{background:#3d1214}.warn{background:#3b2e00}.info{background:#0c2d4a}}</style></head><body>')
[void]$h.Append("<h1>Auditor&iacute;a de equipo: $(HtmlEnc $hostName)</h1><p class=""muted"">Generado $(HtmlEnc ($startUtc.ToString('s') + 'Z')) (UTC) &middot; administrador: $(HtmlEnc $isAdmin) &middot; solo lectura, sin historial de navegaci&oacute;n</p>")

$cards = New-Object System.Text.StringBuilder
function Card([string]$k, [string]$v) { [void]$cards.Append("<div class=""card""><b>$(HtmlEnc $k)</b>$(HtmlEnc $v)</div>") }
if ($system) { Card 'Equipo' ("$($system.Manufacturer) $($system.Model)"); Card 'Sistema' ("$($system.OperatingSystem) $($system.DisplayVersion) (build $($system.BuildNumber))"); Card '~U~ltimo arranque (UTC)' $system.LastBootUtc }
if ($cpu) { Card 'CPU' (@($cpu)[0].Name) }
if ($memory) { Card 'RAM' ("{0} GB total, {1} GB libres, {2} m~o~dulos" -f $memory.TotalGB, $memory.AvailableGB, $memory.ModuleCount) }
if ($wifi -and $wifi.Ssid) { Card 'WiFi conectado' ("$($wifi.Ssid) | $($wifi.Band) canal $($wifi.Channel) | se~n~al $($wifi.SignalPercent) %") }
if ($gateway) { Card 'Gateway' "$($gateway.Address) por $($gateway.Interface)" }
if ($wu) { Card 'Windows Update' ("~u~ltima instalaci~o~n: $(if ($wu.LastInstallSuccess) { $wu.LastInstallSuccess } elseif ($wu.LastSuccessfulInstallHistory) { $wu.LastSuccessfulInstallHistory } else { 'sin dato' })") }
if ($av) { Card 'Antivirus' ((@($av.Products) | ForEach-Object { "$($_.Name) ($(if ($_.Enabled) { 'activo' } else { 'inactivo' }))" }) -join ' | ') }
if ($disks) { Card 'Discos' ((@($disks.PhysicalDisks) | ForEach-Object { "$($_.Name): $($_.HealthStatus)" }) -join ' | ') }
[void]$h.Append("<div class=""cards"">$($cards.ToString())</div>")

$fl = ($flags | ForEach-Object { "<div class=""flag $($_.Level)"">$(HtmlEnc $_.Text)</div>" }) -join ''
[void]$h.Append((Section 'Observaciones' ($fl + '<p class="muted">Reglas simples del script (RAM libre &lt; 15 %, disco no saludable, desgaste &ge; 80 %, CPU &ge; 25 % en la muestra): son avisos para revisar, no diagn&oacute;sticos.</p>')))
if ($system) { [void]$h.Append((Section 'Equipo' (ConvertTo-HtmlTable @($system) @('Hostname','Manufacturer','Model','SerialNumber','BiosVersion','OperatingSystem','OsVersion','TimeZone')))) }
if ($cpu) { [void]$h.Append((Section 'CPU' (ConvertTo-HtmlTable $cpu @('Name','Cores','LogicalProcessors','MaxClockMHz','CurrentClockMHz','LoadPercentNow')))) }
if ($memory) { [void]$h.Append((Section 'RAM: m~o~dulos' (ConvertTo-HtmlTable $memory.Modules @('Slot','Bank','Manufacturer','PartNumber','CapacityGB','SpeedMHz','ConfiguredSpeedMHz','SmbiosMemoryType','FormFactor')))) }
if ($disks) {
    [void]$h.Append((Section 'Discos (SMART seg~u~n Windows)' (ConvertTo-HtmlTable $disks.PhysicalDisks @('Name','MediaType','BusType','SizeGB','HealthStatus','OperationalStatus','TemperatureC','WearPercent','PowerOnHours','ReadErrorsTotal','WriteErrorsTotal'))))
}
if ($processes) {
    [void]$h.Append((Section ("Procesos: top por CPU (muestra de {0} s)" -f $processes.SampleSeconds) (ConvertTo-HtmlTable $processes.TopByCpu @('Name','Instances','CpuPercent','WorkingSetMB'))))
    [void]$h.Append((Section 'Procesos: top por RAM' (ConvertTo-HtmlTable $processes.TopByRam @('Name','Instances','CpuPercent','WorkingSetMB'))))
}
if ($browsers) { [void]$h.Append((Section 'Navegadores' (ConvertTo-HtmlTable $browsers @('Browser','Version','Path')))) }
if ($browserEvents) {
    [void]$h.Append((Section ("Navegadores: cierres y cuelgues (~u~ltimos {0} d~i~as)" -f $EventDays) (ConvertTo-HtmlTable $browserEvents.Events @('TimeUtc','Kind','App','AppVersion','Module'))))
}
if ($crashReports) { [void]$h.Append((Section 'Navegadores: reportes de cierre (solo metadatos)' (ConvertTo-HtmlTable $crashReports @('Browser','Files','NewestUtc','OldestUtc','SizeKB')))) }
if ($adapters) { [void]$h.Append((Section 'Adaptadores de red' (ConvertTo-HtmlTable $adapters @('Name','Description','Status','LinkSpeed','MediaType','DriverVersion','DriverDate','DriverProvider')))) }
if ($netExtra) {
    [void]$h.Append((Section 'Rutas IPv4 (sin multicast ni link-local)' (ConvertTo-HtmlTable $netExtra.Routes @('Destination','NextHop','Interface','AdapterStatus','RouteMetric','InterfaceMetric','Protocol','Store'))))
    [void]$h.Append((Section 'Interfaces IP, VPN y proxy' ((ConvertTo-HtmlTable $netExtra.IpInterfaces @('Interface','ConnectionState','InterfaceMetric','AutomaticMetric','Dhcp')) + '<h3>VPN de Windows</h3>' + (ConvertTo-HtmlTable $netExtra.Vpn @('Name','Scope','Server','Status','TunnelType','SplitTunneling')) + '<h3>Proxy (Internet Settings)</h3>' + (ConvertTo-HtmlTable @($netExtra.Proxy) @('ProxyEnable','ProxyServer','AutoConfigURL','AutoDetect')))))
}
if ($wlan) { [void]$h.Append((Section ("WiFi: eventos de conexi~o~n (~u~ltimos {0} d~i~as)" -f $EventDays) (ConvertTo-HtmlTable $wlan.Events @('TimeUtc','Kind','EventId')))) }
if ($wu) {
    $wuBody = ConvertTo-HtmlTable @($wu) @('LastSearchSuccess','LastInstallSuccess','LastSuccessfulInstallHistory','FailedOrCancelledRecent','ClientFailureEvents','PendingReboot','ServiceStatus','ServiceStartType')
    $wuBody += '<h3>Historial reciente</h3>' + (ConvertTo-HtmlTable $wu.History @('TimeUtc','Operation','Result','Title'))
    $wuBody += '<h3>Actualizaciones (KB) instaladas mas recientes</h3>' + (ConvertTo-HtmlTable $wu.RecentHotFixes @('HotFixID','Description','InstalledOn'))
    $wuBody += '<p class="muted">Las horas vienen del agente de Windows Update y se muestran tal cual (se asumen UTC; no verificado). Umbrales de aviso: instalaci~o~n exitosa de hace mas de 45 d~i~as, b~u~squeda exitosa de hace mas de 14 d~i~as.</p>'
    [void]$h.Append((Section 'Windows Update' $wuBody))
}
if ($av) {
    $avBody = ''
    $avBody += '<h3>Productos registrados en el Centro de seguridad</h3>' + (ConvertTo-HtmlTable $av.Products @('Name','Enabled','SignaturesUpToDate','ProductStateHex'))
    if ($av.Defender) { $avBody += '<h3>Microsoft Defender</h3>' + (ConvertTo-HtmlTable @($av.Defender) @('ServiceEnabled','AntivirusEnabled','RealTimeProtection','BehaviorMonitor','TamperProtected','EngineVersion','SignatureVersion','SignatureAgeDays','QuickScanAgeDays','FullScanAgeDays')) }
    $avBody += ('<h3>Amenazas detectadas (~u~ltimos {0} d~i~as)</h3>' -f $EventDays) + (ConvertTo-HtmlTable $av.Threats @('TimeUtc','ThreatName','Severity','ProcessName','ActionSuccess','Resources'))
    $avBody += '<h3>Procesos del antivirus (muestra de CPU y RAM)</h3>' + (ConvertTo-HtmlTable $av.AvProcesses @('Name','Instances','CpuPercent','WorkingSetMB'))
    $avBody += '<h3>Eventos de Defender (detecciones, fallas, protecci~o~n deshabilitada)</h3>' + (ConvertTo-HtmlTable $av.DefenderEvents @('TimeUtc','EventId','Kind'))
    [void]$h.Append((Section 'Antivirus' $avBody))
}
if ($eventViewer) {
    $evBody = "<p>Leidos: $($eventViewer.Read) eventos de los ultimos $EventDays dias (criticos $($eventViewer.Critical), errores $($eventViewer.Errors), advertencias $($eventViewer.Warnings)).</p>"
    $evBody += '<h3>Indicadores de ca~i~da (Kernel-Power 41, apagado inesperado, BugCheck, Application Error/Hang, WHEA, disco, NTFS, Display)</h3>' + (ConvertTo-HtmlTable $eventViewer.CrashSummary @('Provider','EventId','Count','LastUtc'))
    $evBody += '<h3>~U~ltimos indicadores de ca~i~da</h3>' + (ConvertTo-HtmlTable $eventViewer.Crashes @('TimeUtc','Log','Provider','EventId','Message'))
    $evBody += '<h3>Errores y advertencias mas frecuentes</h3>' + (ConvertTo-HtmlTable $eventViewer.Summary @('Log','Provider','EventId','Level','Count','FirstUtc','LastUtc'))
    $evBody += '<h3>~U~ltimos errores y advertencias</h3>' + (ConvertTo-HtmlTable $eventViewer.Recent @('TimeUtc','Log','Level','Provider','EventId'))
    [void]$h.Append((Section 'Visor de eventos (System y Application)' $evBody))
}
$conn = ''
if ($wifi) { $conn += (ConvertTo-HtmlTable @($wifi) @('Ssid','Bssid','Band','Channel','RadioType','SignalPercent','RxMbps','TxMbps','Authentication')) }
if ($wifiSat -and $wifiSat.AccessPointsSeen -gt 0) {
    $conn += '<h3>Saturaci~o~n de canales (redes vecinas del ~u~ltimo escaneo)</h3>' + (ConvertTo-HtmlTable @($wifiSat) @('AccessPointsSeen','ConnectedBand','ConnectedChannel','OthersOnSameChannel','StrongOthersOnSameChannel','OthersOnOverlappingChannels24','LeastCongested24Of_1_6_11'))
    $conn += (ConvertTo-HtmlTable $wifiSat.Channels @('Band','Channel','AccessPoints','MaxSignal','AvgSignal'))
    $conn += '<p class="muted">En 2.4 GHz los canales se superponen si distan menos de 5 (por eso se cuentan 1, 6 y 11 como los no superpuestos); en 5 GHz solo se cuenta el mismo canal (no se evalua el ancho de canal). Los datos son del ~u~ltimo escaneo de Windows.</p>'
}
if ($gateway) { $conn += (ConvertTo-HtmlTable @($gateway) @('Address','Interface','Description','MediaType')) }
if ($pingResults) { $conn += (ConvertTo-HtmlTable $pingResults @('Role','Target','Sent','Received','LossPercent','MinMs','AvgMs','P95Ms','MaxMs','StdDevMs','JitterMs')) + '<p class="muted">Jitter = promedio de la diferencia entre tiempos de ida y vuelta consecutivos. Gateway e internet por ICMP (resoluci~o~n de 1 ms: en una red local, valores menores de 1 ms figuran como 0); internet-http = peticiones HTTPS a Cloudflare (la primera, de calentamiento, no cuenta; se muestra en FirstRequestMs del JSON). Umbrales de aviso: p~e~rdida &gt; 0 %; gateway: media &gt; 20 ms, jitter &gt; 10 ms; internet: media &gt; 100 ms, jitter &gt; 30 ms; se~n~al &lt; 50 %.</p>' }
if ($conn) { [void]$h.Append((Section ("Conexi~o~n actual y ping al gateway ({0} paquetes)" -f $PingCount) $conn)) }
if ($apps) { [void]$h.Append((Section ("Aplicaciones instaladas ({0})" -f @($apps).Count) (ConvertTo-HtmlTable $apps @('Name','Version','Publisher','InstallDate','LastUseUtc','LastUseSource')))) }
$nt = if ($notes.Count) { '<ul>' + (($notes | ForEach-Object { '<li>' + (HtmlEnc $_) + '</li>' }) -join '') + '</ul>' } else { '<p class="muted">Sin notas.</p>' }
[void]$h.Append((Section 'Notas de la ejecuci~o~n' ($nt + '<p class="muted">~U~ltimo uso: aproximaci~o~n por Prefetch y UserAssist; puede figurar como desconocido. Archivos de la carpeta: report.json, run.log, csv\*.csv (incluye ping-results.csv), wlan-interfaces.txt.</p>')))
[void]$h.Append('</body></html>')
[System.IO.File]::WriteAllText((Join-Path $runDir 'report.html'), (Add-Accents $h.ToString()), $utf8)

Write-Log "Listo. Informe: $(Join-Path $runDir 'report.html')"
if ($Open) { Start-Process (Join-Path $runDir 'report.html') }
