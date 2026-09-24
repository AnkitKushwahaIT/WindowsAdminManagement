# Administrator Audit

Read current direct Administrators membership and save a dated JSON report containing names, SIDs, object types and account sources.

## Configuration

`ReportMaxAgeHours = 24` controls report freshness. Keep the configuration at the top of `Install.ps1` and `Detection.ps1` identical.

## Win32 deployment

Package `Install.ps1` as the setup file. Upload this folder's standalone `Detection.ps1` as the custom detection rule. Use **System** install behavior and **64-bit** detection.

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Install.ps1
```

Use `cmd.exe /c exit 1` for the required uninstall command, disable available uninstall, and do not assign Uninstall. These operations have no automatic rollback. See the [shared Win32 deployment guide](../../../docs/Win32-Administrator-Tools.md) for packaging, report locations, detection behavior and recovery.

## Detection

Requires a matching, unmodified report from a successful run within the configured age. An expired report causes the next Intune evaluation to request installation again.

## Logs and reports

Both scripts append timestamped start, result and error messages to `C:\CompanyIT\AdministratorAudit.log`; change `LogFolder` in both copies if needed. Installation writes JSON reports under `%ProgramData%\WindowsAdminManagement\Win32\AdministratorAudit\`. State directories are restricted to SYSTEM and Administrators. No credentials are stored.

## Scope and pilot checks

Reports direct membership only; it does not expand groups or calculate effective access.

Verify the report contains the expected members and sources, and a stale or missing report returns detection exit 1.

Tests simulate Windows account and scheduled-task operations. Validate the actual Win32 app on a disposable managed pilot device before broader assignment.
