# Extend Temporary Access

Extend the existing removal task to an explicitly approved absolute UTC expiry. It never adds membership or creates a replacement grant.

## Configuration

Set `TargetUserSid`, unique `RequestId`, and `NewExpiryUtc` using `YYYY-MM-DDTHH:MM:SSZ` in both files. The new expiry must be later than or equal to the existing expiry, in the future and no more than 365 days away at execution. Keep the configuration at the top of `Install.ps1` and `Detection.ps1` identical.

## Win32 deployment

Package `Install.ps1` as the setup file. Upload this folder's standalone `Detection.ps1` as the custom detection rule. Use **System** install behavior and **64-bit** detection.

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Install.ps1
```

Use `cmd.exe /c exit 1` for the required uninstall command, disable available uninstall, and do not assign Uninstall. These operations have no automatic rollback. See the [shared Win32 deployment guide](../../../docs/Win32-Administrator-Tools.md) for packaging, report locations, detection behavior and recovery.

## Detection

Checks historical completion of this exact request and report, not whether the user is still an administrator. Expiry therefore does not cause an old Required app to renew access.

## Logs and reports

Both scripts append timestamped start, result and error messages to `C:\CompanyIT\ExtendTemporaryAccess.log`; change `LogFolder` in both copies if needed. Installation writes JSON reports under `%ProgramData%\WindowsAdminManagement\Win32\ExtendTemporaryAccess\`. State directories are restricted to SYSTEM and Administrators. No credentials are stored.

## Scope and pilot checks

Requires a current direct AzureAD member and a valid unexpired repository removal task that is not running. Preserves the task action, principal and settings. Changing an already completed request's settings without a new RequestId is rejected. If execution succeeded but receipt writing failed, retrying the same absolute expiry does not add more time.

Test the requested UTC time, membership disappearing, an expired/running task, schedule update failure, repeated execution, and successful detection after the grant eventually expires.

Tests simulate Windows account and scheduled-task operations. Validate the actual Win32 app on a disposable managed pilot device before broader assignment.

