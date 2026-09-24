# Administrator Changes

Compare direct administrator membership against the previous successful snapshot and log additions/removals by SID.

## Configuration

Set `ReportMaxAgeHours` in both files. Default: 24 hours. Keep the configuration at the top of `Install.ps1` and `Detection.ps1` identical.

## Win32 deployment

Package `Install.ps1` as the setup file. Upload this folder's standalone `Detection.ps1` as the custom detection rule. Use **System** install behavior and **64-bit** detection.

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Install.ps1
```

Use `cmd.exe /c exit 1` for the required uninstall command, disable available uninstall, and do not assign Uninstall. These operations have no automatic rollback. See the [shared Win32 deployment guide](../../../docs/Win32-Administrator-Tools.md) for packaging, report locations, detection behavior and recovery.

## Detection

Requires a fresh, unmodified report and matching receipt. Refresh follows Intune reevaluation; it is not an exact 24-hour scheduler.

## Logs and reports

Both scripts append timestamped start, result and error messages to `C:\CompanyIT\AdministratorChanges.log`; change `LogFolder` in both copies if needed. Installation writes JSON reports under `%ProgramData%\WindowsAdminManagement\Win32\AdministratorChanges\`. State directories are restricted to SYSTEM and Administrators. No credentials are stored.

## Scope and pilot checks

The first run establishes a baseline and reports no changes. Later comparisons retain dated JSON history before advancing the baseline. Changes that occur and are reversed between snapshots are not captured, and the report does not identify who performed them. A corrupt baseline causes failure rather than being silently reset.

Establish a baseline, add and remove test members, rerun and inspect both current and history reports. Also test an empty group baseline and corrupt baseline handling.

Tests simulate Windows account and scheduled-task operations. Validate the actual Win32 app on a disposable managed pilot device before broader assignment.
