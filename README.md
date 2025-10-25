# Windows-11-Pro-to-Enterprise---Silent-Upgrade
A PowerShell script to silently update a Windows 11 machine from Pro to Enterprise (with no reboots or prompts for users)

## Overview
This PowerShell script upgrades Windows 11 Pro systems to Enterprise using a Multiple Activation Key (MAK) silently, without user prompts, pop-ups, or a reboot.  
It is designed for remote deployment through RMM tools such as Syxsense, Intune, or Configuration Manager, and runs under the SYSTEM account.

Unlike most activation scripts, this one:

- Performs an early-exit check to avoid modifying already activated Enterprise devices (so it's safe to run multiple times).
- Works even if Windows Script Host is disabled for SYSTEM.
- Activates through WMI, avoiding VBScript UI.
- Logs actions to `C:\ProgramData\WinEntUpgrade\upgrade.log`.
- Outputs a single JSON line at the end for easy parsing by RMM tools.

---

## Example Outputs

If Windows 11 was already Enterprise + activated:
```
=== Enterprise flip + activation (MAK) as: nt authority\system ===
  Current: Edition=Enterprise; Activated=True; KeyTail=63BPF
  {"ok":true,"message":"Already Enterprise and
activated","edition":"Enterprise","keyTail":"63BPF"}
```

If Windows 11 was not activated yet (or was on Pro edition):
```
=== Enterprise flip + activation (MAK) as: nt authority\system ===
  Current: Edition=Pro; Activated=False; KeyTail=
  Installing MAK key via WMI...
  Activating via WMI...
  Final: Edition=Enterprise; Activated=True; KeyTail=63BPF
  {"ok":true,"message":"Enterprise
activated","edition":"Enterprise","keyTail":"63BPF"}
  SUCCESS - This machine now has Enterprise edition and is permanently
activated.
```


## Features

| Feature | Description |
|----------|-------------|
| Silent execution | No GUI pop-ups or licensing dialogs. Fully background-safe. |
| No reboot required | Edition and activation take effect immediately after success. |
| Self-detecting | Automatically skips systems already on Enterprise and activated. |
| WSH-aware | Falls back to WMI activation if Windows Script Host is disabled. |
| Detailed logging | All actions and results are logged to `C:\ProgramData\WinEntUpgrade\upgrade.log`. |
| System-safe | Runs under `NT AUTHORITY\SYSTEM`, suitable for RMM, Intune, or scheduled tasks. |
| MAK-only | Uses a Multiple Activation Key (MAK). KMS activation is not supported or configured. |

---

## What It Does

1. Checks the current Windows edition and activation status using WMI and `/xpr`.
2. If already Enterprise and activated, exits immediately.
3. Otherwise:
   - Ensures the Software Protection service (`sppsvc`) is running.
   - Syncs system time (`w32tm /resync`).
   - Installs the MAK key silently via WMI.
   - Activates Windows silently via WMI.
4. Verifies activation and prints a JSON summary.

Example success output:
```json
{"ok":true,"message":"Enterprise activated","edition":"Enterprise","keyTail":"63BPF"}
```

Example skip output:
```json
{"ok":true,"message":"Already Enterprise and activated","edition":"Enterprise","keyTail":"63BPF"}
```

---

## Usage

### 1. Edit the script
Open the `.ps1` file and replace this line with your actual MAK key:
```powershell
$MAK = 'YOUR-MAK-KEY-HERE'
```

MAK keys are provided through Microsoft Volume Licensing (VLSC).  
This script does not support KMS keys or AAD-based activation.

### 2. Deploy
Run the script:

- Locally as Administrator in an elevated PowerShell session.
- Remotely via Syxsense, Intune, or Configuration Manager under the SYSTEM context.

Example command:
```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Temp\FlipToEnterprise.ps1"
```

### 3. Review results
Logs are written to:
```
C:\ProgramData\WinEntUpgrade\upgrade.log
```
The final console line (or RMM-captured output) is JSON showing the result.

---

## Example Automation Flow

| Step | Purpose | Script |
|------|----------|--------|
| 1 | Audit all endpoints for edition and activation status | `Check-WindowsEditionStatus.ps1` (optional companion) |
| 2 | Run the Enterprise upgrade script only where `Edition != Enterprise` or `Activated == false` | `FlipToEnterprise.ps1` |
| 3 | Re-audit for confirmation | `Check-WindowsEditionStatus.ps1` again |

---

## Output Summary

| Field | Meaning |
|--------|----------|
| `ok` | True if the process succeeded or no action was needed |
| `message` | Summary of what happened |
| `edition` | Final Windows edition |
| `keyTail` | Last five characters of the installed MAK |
| `hint` | Log file location (only shown on error) |

---

## Notes and Requirements

- Requires Windows 11 Pro or higher.
- Must run under elevated privileges (Administrator or SYSTEM).
- Requires outbound HTTPS (TCP 443) to Microsoft activation servers.
- Tested on Windows 11 23H2 and 24H2 builds.
- No reboot required.

---

## Example Log Output

Location: `C:\ProgramData\WinEntUpgrade\upgrade.log`

```
[2025-10-22T20:35:12] === Enterprise flip + activation (MAK) as: NT AUTHORITY\SYSTEM ===
[2025-10-22T20:35:12] Current: Edition=Pro; Activated=False; KeyTail=
[2025-10-22T20:35:14] Installing MAK key via WMI...
[2025-10-22T20:35:16] Activating via WMI...
[2025-10-22T20:35:20] Final: Edition=Enterprise; Activated=True; KeyTail=63BPF
```

---

## Example JSON Results

| Scenario | JSON Output |
|-----------|--------------|
| Already Enterprise | `{"ok":true,"message":"Already Enterprise and activated","edition":"Enterprise","keyTail":"63BPF"}` |
| Newly Activated | `{"ok":true,"message":"Enterprise activated","edition":"Enterprise","keyTail":"63BPF"}` |
| Error | `{"ok":false,"message":"Activation not confirmed. See log for details.","hint":"See C:\\ProgramData\\WinEntUpgrade\\upgrade.log"}` |

---

## License
# No license 
# Author: Brandon Jones  
