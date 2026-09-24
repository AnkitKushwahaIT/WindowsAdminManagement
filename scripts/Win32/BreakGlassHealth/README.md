# Break Glass Health

Check that the configured local recovery account exists, is enabled and is a direct member of Administrators. No account or password changes are made.

## Configuration

Set `UserName` in both files. Default: `LocalAdmin`. Set `ReportMaxAgeHours` for report refresh. Keep the configuration at the top of `Install.ps1` and `Detection.ps1` identical.

## Win32 deployment

Package `Install.ps1` as the setup file. Upload this folder's standalone `Detection.ps1` as the custom detection rule. Use **System** install behavior and **64-bit** detection.

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Install.ps1
```

Use `cmd.exe /c exit 1` for the required uninstall command, disable available uninstall, and do not assign Uninstall. These operations have no automatic rollback. See the [shared Win32 deployment guide](../../../docs/Win32-Administrator-Tools.md) for packaging, report locations, detection behavior and recovery.

## Detection

Uses current account/membership state and a fresh successful report. The installer records findings and exits 1 if unhealthy; it does not fix the account.

## Logs and reports

Both scripts append timestamped start, result and error messages to `C:\CompanyIT\BreakGlassHealth.log`; change `LogFolder` in both copies if needed. Installation writes JSON reports under `%ProgramData%\WindowsAdminManagement\Win32\BreakGlassHealth\`. State directories are restricted to SYSTEM and Administrators. No credentials are stored.

## Scope and pilot checks

Does not authenticate, test logon rights, retrieve a password, rotate a password, or prove that the account is usable for recovery.

Test a healthy account, a disabled account, an absent account and missing administrator membership.

Tests simulate Windows account and scheduled-task operations. Validate the actual Win32 app on a disposable managed pilot device before broader assignment.

