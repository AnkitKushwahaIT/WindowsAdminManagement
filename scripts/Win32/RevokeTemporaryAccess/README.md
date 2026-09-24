# Revoke Temporary Access

Remove an explicitly selected temporary administrator early, verify removal, and unregister the corresponding removal task.

## Configuration

Set `TargetUserSid` and a unique `RequestId` in both files. Blank values are deliberately rejected. Use one Win32 app/request per approved target action. Keep the configuration at the top of `Install.ps1` and `Detection.ps1` identical.

## Win32 deployment

Package `Install.ps1` as the setup file. Upload this folder's standalone `Detection.ps1` as the custom detection rule. Use **System** install behavior and **64-bit** detection.

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Install.ps1
```

Use `cmd.exe /c exit 1` for the required uninstall command, disable available uninstall, and do not assign Uninstall. These operations have no automatic rollback. See the [shared Win32 deployment guide](../../../docs/Win32-Administrator-Tools.md) for packaging, report locations, detection behavior and recovery.

## Detection

Checks the matching successful request receipt and its report. Once completed, later detection stays successful even if the user receives a new grant. This prevents an old Required assignment from repeatedly revoking future approvals.

## Logs and reports

Both scripts append timestamped start, result and error messages to `C:\CompanyIT\RevokeTemporaryAccess.log`; change `LogFolder` in both copies if needed. Installation writes JSON reports under `%ProgramData%\WindowsAdminManagement\Win32\RevokeTemporaryAccess\`. State directories are restricted to SYSTEM and Administrators. No credentials are stored.

## Scope and pilot checks

A current member must be a direct AzureAD user with a recognizable enabled repository removal task; potentially permanent or unsupported access is refused. If both membership and task are already absent, the request is recorded as completed. Removing group membership does not revoke existing logon tokens.

Test removal and task deletion, removal failure retaining the task, repeated execution with no additional changes, and a later new grant remaining untouched by the completed request.

Tests simulate Windows account and scheduled-task operations. Validate the actual Win32 app on a disposable managed pilot device before broader assignment.

