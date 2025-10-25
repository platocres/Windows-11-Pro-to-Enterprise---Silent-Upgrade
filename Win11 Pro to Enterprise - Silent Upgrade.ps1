<#
===============================================================
        Win11 Pro to Enterprise - Silent Upgrade.ps1
===============================================================
.SYNOPSIS
  Upgrades Windows 11 Pro → Enterprise silently using a hard-coded MAK
key, and activates it.
  Works under SYSTEM (for RMM/Intune/Syxsense deployment).
  Safe to re-run — will skip if already Enterprise + activated.

.DESCRIPTION
  - Checks edition & activation status using WMI (and /xpr as fallback)
  - If not Enterprise or not activated, installs MAK and activates silently
  - Works even if Windows Script Host (WSH) is disabled for SYSTEM
(uses WMI fallback)
  - Logs everything to C:\ProgramData\WinEntUpgrade\upgrade.log
  - Returns JSON summary for easy RMM parsing
  - Exit 0 = success, Exit 2 = error

.OUTPUT
If already Enterprise + activated:
  === Enterprise flip + activation (MAK) as: nt authority\system ===
  Current: Edition=Enterprise; Activated=True; KeyTail=63BPF
  {"ok":true,"message":"Already Enterprise and
activated","edition":"Enterprise","keyTail":"63BPF"}

If not activated yet (or Pro edition):
  === Enterprise flip + activation (MAK) as: nt authority\system ===
  Current: Edition=Pro; Activated=False; KeyTail=
  Installing MAK key via WMI...
  Activating via WMI...
  Final: Edition=Enterprise; Activated=True; KeyTail=63BPF
  {"ok":true,"message":"Enterprise
activated","edition":"Enterprise","keyTail":"63BPF"}
  SUCCESS - This machine now has Enterprise edition and is permanently
activated.

  Developed by Brandon Jones
#>

$ErrorActionPreference = 'Stop'

# === [1] SET YOUR MAK HERE ===
$MAK = 'INSERT PRODUCT KEY HERE'   # Example:AAAAA-BBBBB-CCCCC-DDDDD-EEEEE

# === [2] CONFIGURATION ===
$LogPath = 'C:\ProgramData\WinEntUpgrade\upgrade.log'
$LogDir  = Split-Path $LogPath -Parent
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path
$LogDir -Force | Out-Null }

# --- [3] UTILITY FUNCTIONS ---
function Step($m){
  Write-Host $m
  Add-Content -Path $LogPath -Value ("[" + (Get-Date).ToString('s') + "] " + $m)
}

function SlmgrPath {
  if ([Environment]::Is64BitOperatingSystem -and -not
[Environment]::Is64BitProcess) { "$env:WINDIR\Sysnative\slmgr.vbs" }
  else { "$env:WINDIR\System32\slmgr.vbs" }
}

function Get-Edition { (Get-ItemProperty
'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID }

# Try to run slmgr /xpr and parse output
function Get-XprText {
  try {
    $out = & "$env:WINDIR\System32\cscript.exe" //B //Nologo
(SlmgrPath) /xpr 2>&1
    ($out -join ' ')
  } catch { '' }
}

# Returns true if machine reports “permanently activated”
function Is-PermanentlyActivated {
  $txt = Get-XprText
  if ([string]::IsNullOrEmpty($txt)) { return $false }
  return ($txt -match 'permanently activated')
}

# Get the SoftwareLicensingProduct instance for Windows OS
function Get-WinProd {
  Get-CimInstance SoftwareLicensingProduct -Filter "Description like
'Windows%Operating System%' and PartialProductKey is not null" |
    Sort-Object LicenseStatus -Descending | Select-Object -First 1
}

# Install MAK using WMI
function WMI-InstallKey($key){
  $svc = Get-WmiObject -Class SoftwareLicensingService
  ($svc.InstallProductKey($key)).ReturnValue
}

# Activate using WMI
function WMI-Activate {
  $prod = Get-WmiObject -Query "SELECT * FROM SoftwareLicensingProduct
WHERE Description LIKE 'Windows%Operating System%' AND
PartialProductKey IS NOT NULL" | Select-Object -First 1
  if ($prod) { ($prod.Activate()).ReturnValue } else { 9999 }
}

# === [4] MAIN EXECUTION ===
try {
  if ([string]::IsNullOrWhiteSpace($MAK)) { throw "MAK key not set in script." }

  Step ("=== Enterprise flip + activation (MAK) as: " + (whoami) + " ===")

  # --- Early-exit check (fixed) ---
  # Use WMI first (more reliable under SYSTEM), then /xpr fallback.
  $ed0 = Get-Edition
  $p0 = Get-WinProd
  $active0 = $false
  if ($p0 -and $p0.LicenseStatus -eq 1) { $active0 = $true }
  elseif (Is-PermanentlyActivated) { $active0 = $true }
  $tail0 = if ($p0) { $p0.PartialProductKey } else { "" }
  Step ("Current: Edition=" + $ed0 + "; Activated=" + $active0 + ";
KeyTail=" + $tail0)

  if (($ed0 -match 'Enterprise') -and $active0) {
    # Already good → exit cleanly
    $ok = [ordered]@{ ok=$true; message='Already Enterprise and
activated'; edition=$ed0; keyTail=$tail0 }
    ($ok | ConvertTo-Json -Compress) | Write-Output
    exit 0
  }

  # --- Ensure Software Protection service (sppsvc) is running ---
  $spp = Get-Service sppsvc -ErrorAction SilentlyContinue
  if ($spp -and $spp.Status -ne 'Running') {
    Step 'Starting sppsvc...'
    Start-Service sppsvc
    $spp.WaitForStatus('Running','00:00:15')
  }

  # --- Sync time (prevents activation issues with clock drift) ---
  try { Step 'w32tm /resync'; w32tm /resync | Out-Null } catch { Step
('w32tm failed: ' + $_.Exception.Message) }

  # --- Install MAK silently via WMI (bypasses WSH restrictions) ---
  Step 'Installing MAK key via WMI...'
  $r1 = WMI-InstallKey $MAK
  Add-Content -Path $LogPath -Value ("WMI InstallProductKey => " + $r1)

  # --- Activate silently via WMI ---
  Step 'Activating via WMI...'
  $r2 = WMI-Activate
  Add-Content -Path $LogPath -Value ("WMI Activate => " + $r2)
  Start-Sleep -Seconds 3

  # --- Verify activation ---
  $edF = Get-Edition
  $pF = Get-WinProd
  $tailF = if ($pF) { $pF.PartialProductKey } else { "" }
  $activeF = $false
  if ($pF -and $pF.LicenseStatus -eq 1) { $activeF = $true }
  elseif (Is-PermanentlyActivated) { $activeF = $true }

  Step ("Final: Edition=" + $edF + "; Activated=" + $activeF + ";
KeyTail=" + $tailF)

  if (-not ($edF -match 'Enterprise')) {
    $bad = [ordered]@{ ok=$false; message=("Edition is not Enterprise
(Edition=" + $edF + ").") }
    ($bad | ConvertTo-Json -Compress) | Write-Output
    exit 2
  }
  if (-not $activeF) {
    $bad2 = [ordered]@{ ok=$false; message='Activation not confirmed.
See log for details.' }
    ($bad2 | ConvertTo-Json -Compress) | Write-Output
    exit 2
  }

  # --- Success output ---
  $ok2 = [ordered]@{ ok=$true; message='Enterprise activated';
edition=$edF; keyTail=$tailF }
  ($ok2 | ConvertTo-Json -Compress) | Write-Output
  Step 'This machine now has Enterprise edition and is permanently activated. '
  exit 0
}
catch {
  # --- Error handler ---
  $err = $_.Exception.Message
  Step ('ERROR: ' + $err)
  $bad3 = [ordered]@{ ok=$false; message=$err; hint=('See ' + $LogPath) }
  ($bad3 | ConvertTo-Json -Compress) | Write-Output
  exit 2
}


Page 9 of 10 Page 10 of 10
