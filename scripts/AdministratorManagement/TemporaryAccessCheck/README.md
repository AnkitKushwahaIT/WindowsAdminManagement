# Temporary Access Check

Check that each direct AzureAD user administrator, except explicitly permanent members, has an enabled, unexpired SYSTEM removal task.

## Configuration

Set `PermanentEntraAdminSids` for permanently approved direct Entra users. The empty default treats every direct AzureAD user as temporary. Set `ReportMaxAgeHours` for report refresh. Keep the configuration at the top of `Install.ps1` and `Detection.ps1` identical.

## Win32 deployment

Package `Install.ps1` as the setup file. Upload this folder's standalone `Detection.ps1` as the custom detection rule. Use **System** install behavior and **64-bit** detection.

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Install.ps1
```

Use `cmd.exe /c exit 1` for the required uninstall command, disable available uninstall, and do not assign Uninstall. These operations have no automatic rollback. See the [shared Win32 deployment guide](../../../docs/Win32-Administrator-Tools.md) for packaging, report locations, detection behavior and recovery.

## Detection

Checks live membership/task state and report freshness. Missing, expired or unexpected removal tasks return exit 1. The installer writes a report but does not create or repair tasks.

## Logs and reports

Both scripts append timestamped start, result and error messages to `C:\CompanyIT\TemporaryAccessCheck.log`; change `LogFolder` in both copies if needed. Installation writes JSON reports under `%ProgramData%\WindowsAdminManagement\Win32\TemporaryAccessCheck\`. State directories are restricted to SYSTEM and Administrators. No credentials are stored.

## Scope and pilot checks

Supports the task format created by `scripts/TemporaryAdmin/Grant-TemporaryLocalAdmin.ps1`. It does not identify an Entra user from an unresolved SID-only entry, inspect inherited rights, or guarantee that an administrator cannot tamper with tasks.

Check a valid grant, a disabled task, an expired task, an altered action and a permanently approved user.

Tests simulate Windows account and scheduled-task operations. Validate the actual Win32 app on a disposable managed pilot device before broader assignment.
