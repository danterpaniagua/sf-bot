#!/usr/bin/env bash
# Event: 20260923_gitin2099-jenkins-service-crash-loop (GITIN-2099)
# Mixed PowerShell (SFCG-JENKINS-01, Windows) and bash (sfcg-sonarqube, Linux)
# commands, run manually by the user and results pasted back. Grouped by phase.

# === INVESTIGATION (SFCG-JENKINS-01, PowerShell) ===

# C1 — confirm host + service state + Java setup
: <<'PS1'
"Running on: $env:COMPUTERNAME"
Get-WmiObject Win32_Service -Filter "Name='Jenkins'" | Select-Object Name, State, PathName, StartMode
Get-Command java -All -ErrorAction SilentlyContinue | Select-Object Source
PS1

# C2 — inspect WinSW wrapper log and Jenkins' own stdout/stderr logs
: <<'PS1'
Get-ChildItem "D:\Program Files\Jenkins\" -Filter "*.log" | Select-Object Name, LastWriteTime, Length
Get-Content "D:\Program Files\Jenkins\jenkins.err.log" -Tail 60 -ErrorAction SilentlyContinue
PS1
# Result: "Running with Java 17... older than the minimum required version (Java 21)"
# on every restart attempt — root cause confirmed.

# C3 — confirm WinSW service config (jenkins.xml)
: <<'PS1'
Get-Content "D:\Program Files\Jenkins\jenkins.xml"
PS1
# Result: <executable>C:\Program Files\Java\jdk-17\bin\java.exe</executable>,
# <onfailure action="restart"/> with no backoff — confirms the infinite loop mechanism.

# === REMEDIATION 1 — install JDK 21 and repoint jenkins.xml (SFCG-JENKINS-01) ===

# D1 — resolve real Temurin 21 installer URL via Adoptium's API and download
: <<'PS1'
$asset = Invoke-RestMethod -Uri "https://api.adoptium.net/v3/assets/latest/21/hotspot?image_type=jdk&os=windows&architecture=x64"
$msiUrl = $asset[0].binary.installer.link
Invoke-WebRequest -Uri $msiUrl -OutFile "$env:TEMP\temurin21.msi"
PS1

# D2 — install
: <<'PS1'
Start-Process msiexec.exe -ArgumentList "/i `"$env:TEMP\temurin21.msi`" /quiet /norestart" -Wait
Get-ChildItem "C:\Program Files\Eclipse Adoptium\jdk-21*\bin\java.exe"
PS1
# Result: C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\bin\java.exe

# D3 — backup and repoint jenkins.xml, restart service
: <<'PS1'
$path = "D:\Program Files\Jenkins\jenkins.xml"
Copy-Item $path "$path.bak-GITIN-2099" -Force
(Get-Content $path -Raw) -replace [regex]::Escape('C:\Program Files\Java\jdk-17\bin\java.exe'), 'C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\bin\java.exe' | Set-Content $path
Restart-Service Jenkins
Get-Service Jenkins | Select-Object Name, Status
Get-Content "D:\Program Files\Jenkins\jenkins.err.log" -Tail 30
PS1
# Result: Status Running, stable; no more "Java 17" warning.

# === REMEDIATION 2 — Windows Firewall rule scoped to old java.exe path ===

# D4 — diagnose: rule looked correct (Allow/Any/Any) but had a Program filter
: <<'PS1'
Get-NetFirewallRule -DisplayName "Jenkins" | Get-NetFirewallApplicationFilter | Select-Object Program
PS1
# Result: C:\Program Files\Java\jdk-17\bin\java.exe (stale)

# D5 — fix: repoint the rule's program filter, re-enable firewall (user had
# disabled it entirely as a stopgap — reverted in favor of the real fix)
: <<'PS1'
Get-NetFirewallRule -DisplayName "Jenkins" | Get-NetFirewallApplicationFilter | Set-NetFirewallApplicationFilter -Program "C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\bin\java.exe"
Set-NetFirewallProfile -All -Enabled True
Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction
PS1

# === REMEDIATION 3 — system PATH/JAVA_HOME + reboot (SonarScanner's own java resolution) ===

# D6 — update machine-level JAVA_HOME and swap the Java entry in PATH
: <<'PS1'
[Environment]::SetEnvironmentVariable("JAVA_HOME", "C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot", "Machine")
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$newPath = ($machinePath -split ";" | ForEach-Object { if ($_ -like "*Java\jdk-17*") { "C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\bin" } else { $_ } }) -join ";"
[Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
PS1
# Result confirmed NOT to propagate to already-running processes/services or
# even a freshly Start-Process'd shell — Windows caches env at boot time.

# D7 — full VM reboot (only way to make D6 take effect)
: <<'AZ'
az vm restart \
  --name SFCG-JENKINS-01 \
  --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
AZ

# D8 — post-reboot verification
: <<'PS1'
Get-Service Jenkins | Select-Object Name, Status
cmd /c "java -version"
Test-NetConnection -ComputerName localhost -Port 8443
PS1
# Result: Running, java -version -> 21.0.12.1, port listening. Confirmed fixed.

# === REMEDIATION 4 — sfcg-sonarqube shared Jenkins agent (bash, Linux) ===

# D9 — diagnose: Temurin 21 already installed, just not the active default
hostname
java -version
update-alternatives --list java
ls /usr/lib/jvm/

# D10 — fix
sudo update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java
java -version

# D11 — verify zero impact on SonarQube itself (independently pinned via SONAR_JAVA_PATH)
curl -s http://127.0.0.1:9000/api/system/status
systemctl status sonarqube --no-pager
cat /etc/systemd/system/sonarqube.service.d/*.conf
ps aux | grep -i sonar | grep java

# === HALLAZGO SECUNDARIO 1 — LOCAL_GIT_COMMIT_MESSAGE fix (sf-devops repo, local) ===
# Fixed all 23 SF-LOYALTY jenkinsfiles' `post { failure { ... } } ` blocks to
# independently fetch LOCAL_GIT_COMMIT_MESSAGE (previously only set in the
# sibling `success` block — success/failure are mutually exclusive, so a
# failing build always crashed the failure-notification step itself).
: <<'BASH'
cd /home/dpaniagua/Documentos/git/sf-devops
git add jenkins/SF-LOYALTY/jenkinsfiles/
git commit -m "fix: agrega LOCAL_GIT_COMMIT_MESSAGE faltante en bloques failure de notificacion Google Chat (SF-LOYALTY)"
git push origin main
BASH

# === HALLAZGO SECUNDARIO 2 — packProject.ps1 orphaned-build-file crash ===
# Fixed the wildcard-zip-only existence check that assumed a paired .build
# file always exists; now requires both, falling through to a normal fresh
# backup otherwise (self-heals the orphaned state).
: <<'BASH'
cd /home/dpaniagua/Documentos/git/sf-devops
git add jenkins/SF-LOYALTY/scripts/powershell/packProject.ps1
git commit -m "fix: packProject.ps1 no rompe si existe un zip huerfano sin su .build correspondiente"
git push origin main
BASH
