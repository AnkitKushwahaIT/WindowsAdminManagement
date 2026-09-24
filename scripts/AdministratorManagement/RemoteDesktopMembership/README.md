# Remote Desktop Membership

Add/remove explicitly configured SIDs in Remote Desktop Users, independently of administrator membership.

## Configuration

Populate `MemberSidsToAdd` and/or `MemberSidsToRemove` in both scripts. Both empty is rejected; the same SID cannot be in both lists. All other members are preserved. Keep the configuration at the top of `Install.ps1` and `Detection.ps1` identical.

## Win32 deployment

Package `Install.ps1` as the setup file. Upload this folder's standalone `Detection.ps1` as the custom detection rule. Use **System** install behavior and **64-bit** detection.

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Install.ps1
```

Use `cmd.exe /c exit 1` for the required uninstall command, disable available uninstall, and do not assign Uninstall. These operations have no automatic rollback. See the [shared Win32 deployment guide](../../../docs/Win32-Administrator-Tools.md) for packaging, report locations, detection behavior and recovery.

## Detection

Checks live Remote Desktop Users membership. Exit 0 with stdout means all requested additions exist and all requested removals are absent, even if installation never needed to run.

## Logs and reports

Both scripts append timestamped start, result and error messages to `C:\CompanyIT\RemoteDesktopMembership.log`; change `LogFolder` in both copies if needed. Installation writes JSON reports under `%ProgramData%\WindowsAdminManagement\Win32\RemoteDesktopMembership\`. State directories are restricted to SYSTEM and Administrators. No credentials are stored.

## Scope and pilot checks

Does not enable Remote Desktop, configure firewall rules, grant user logon rights, override deny policies, or guarantee a successful remote sign-in. Under a Required assignment, later drift can cause configured membership changes to be reapplied. Suspend the assignment before manual rollback.

Test selected additions/removals, preservation of unrelated members, conflicting configuration, failed operations and detection of later drift.

Tests simulate Windows account and scheduled-task operations. Validate the actual Win32 app on a disposable managed pilot device before broader assignment.
