# Approved Administrator Check

Compare every direct administrator member with the approved SID list and recognize valid temporary grants when enabled. It reports drift without removing anyone.

## Configuration

Populate `ApprovedAdminSids` in both files, including approved local accounts, built-in accounts and groups. An empty list is rejected. `RecognizeTemporaryGrants = $true` allows valid, unexpired tasks created by the repository temporary-grant script. `ReportMaxAgeHours = 24` controls report refresh. Keep the configuration at the top of `Install.ps1` and `Detection.ps1` identical.

## Win32 deployment

Package `Install.ps1` as the setup file. Upload this folder's standalone `Detection.ps1` as the custom detection rule. Use **System** install behavior and **64-bit** detection.

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Install.ps1
```

Use `cmd.exe /c exit 1` for the required uninstall command, disable available uninstall, and do not assign Uninstall. These operations have no automatic rollback. See the [shared Win32 deployment guide](../../../docs/Win32-Administrator-Tools.md) for packaging, report locations, detection behavior and recovery.

## Detection

Evaluates live membership and requires a fresh successful report. Unexpected members return exit 1; the installer saves findings and also returns 1 until the policy or membership is corrected.

## Logs and reports

Both scripts append timestamped start, result and error messages to `C:\CompanyIT\ApprovedAdministratorCheck.log`; change `LogFolder` in both copies if needed. Installation writes JSON reports under `%ProgramData%\WindowsAdminManagement\Win32\ApprovedAdministratorCheck\`. State directories are restricted to SYSTEM and Administrators. No credentials are stored.

## Scope and pilot checks

An intentionally disabled built-in Administrator still occupies the group. Include its actual SID if approved. A temporary exception is recognized only for a direct AzureAD user with a matching valid task; unknown or expired tasks do not create exceptions. This package does not change existing cleanup enforcement.

Test an approved set, an unexpected local member, a valid temporary grant, and a missing/disabled/expired removal task.

Tests simulate Windows account and scheduled-task operations. Validate the actual Win32 app on a disposable managed pilot device before broader assignment.
