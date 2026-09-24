# Administrator management tools for Intune Win32 apps

Each folder under `scripts/AdministratorManagement` is a separate Win32 app: an `Install.ps1`, a standalone `Detection.ps1`, and a short deployment guide. Every script follows configuration, timestamped logging, validation, action/check, verification, completion and error handling. Existing repository scripts are unchanged.

## Packages

| Folder | Purpose | Changes account access? | Detection checks |
| --- | --- | --- | --- |
| AdministratorAudit | Inventory direct Administrators membership | No | Report freshness and integrity |
| ApprovedAdministratorCheck | Check approved SIDs and valid temporary exceptions | No | Live policy result and fresh successful report |
| TemporaryAccessCheck | Check expiry and removal tasks for direct Entra users | No | Live task/membership result and fresh successful report |
| RevokeTemporaryAccess | End one approved temporary grant early | Yes | Completion of the specific request |
| ExtendTemporaryAccess | Move an existing removal task to an approved UTC expiry | Schedule only; never grants membership | Completion of the specific request |
| BreakGlassHealth | Check account existence, enabled state and direct admin membership | No | Live health result and fresh successful report |
| AdministratorChanges | Compare membership with the previous snapshot | No | Report freshness and integrity |
| RemoteDesktopMembership | Apply selected Remote Desktop Users additions/removals | Yes, RDP group only | Live desired membership |

## Configure and package

1. Make a private copy of the selected package folder. Set matching configuration values at the top of **both scripts**. Blank target/request/approval lists that require administrator input deliberately fail rather than guessing.
2. Keep `AppVersion`, account names, SID lists, report age, target SID, request ID and expiry identical between the two copies. Only include verified SIDs; no email-domain matching is used.
3. Put `Install.ps1` alone in a source folder. Keep your configured `Detection.ps1` outside the source folder for separate upload. The scripts have no external helper-file dependency.
4. Package using the [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool), for example:

```powershell
.\IntuneWinAppUtil.exe -c C:\Packages\AdminTool\Source -s Install.ps1 -o C:\Packages\AdminTool\Output -q
```

5. Upload the resulting `.intunewin` as a Windows app (Win32). Assign to a pilot device group first.

| Intune setting | Value |
| --- | --- |
| Installer type | Command line |
| Install behavior | System |
| Architecture | Your piloted 64-bit Windows devices |
| Minimum OS | A supported Windows version validated in your environment |
| Detection rule | Use a custom detection script: this package's Detection.ps1 |
| Run detection as 32-bit on 64-bit clients | No |
| Signature check | No for unsigned scripts, or sign and deploy certificate trust first |
| Return codes | 0 = Success; 1 = Failed |
| Restart behavior | No specific action; scripts do not request a restart |
| Allow available uninstall | No |

Install command:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Install.ps1
```

Use `cmd.exe /c exit 1` if the form requires an uninstall command. Do not assign Uninstall: these scripts do not have a universal safe reversal. This placeholder fails explicitly instead of pretending to undo access changes. To roll back RDP membership, stop the assignment and apply reviewed inverse SID lists. To undo an extension, review the scheduled task through your approved administrative process. Revocation does not automatically restore access.

No runtime prompts, passwords or credentials are required. Scripts use Windows PowerShell 5.1, LocalAccounts and, where relevant, ScheduledTasks.

## Detection and refresh

Every detection script returns exit 0 **with nonempty stdout** only when its documented condition passes. Drift, stale reports, incomplete requests and errors return 1 without console output. Details go to the local log. Installers also write no console status messages: they use file logging and exit codes.

Audit/change reports use `ReportMaxAgeHours` (default 24). Detection requires a recent successful report with matching configuration/version and an unchanged report hash. Intune can rerun a Required app when that report becomes stale at a subsequent evaluation. This does not promise an exact hourly or daily execution time.

Approved-admin, temporary-access and break-glass checks also evaluate current state. If unhealthy, the installer writes findings and returns failure; it does not silently remediate accounts. Those Required apps can retry and continue to show failures until an administrator resolves the findings or updates policy. Their Intune app status is a monitoring signal, not a formal Intune compliance policy.

For one-time extension/revocation, create a unique `RequestId` for each approval and deploy that request to the intended devices. The matching completion receipt is intentionally historical. Otherwise an expired grant or a later legitimate grant could cause an old Required assignment to renew or revoke access again. A changed configuration with an already used request ID is rejected. Create a new request ID/app for another action; retain the old receipts. Do not delete receipts to request retries or renewals.

Do not run concurrent extension/revocation requests for the same user. Coordinate those requests and allow the previous action to complete first.

An extension uses an **absolute UTC expiry**, not "add another five days whenever installation reruns." It requires active membership and a valid unexpired task, preserves its removal action, and does not recreate expired or revoked access. Detection of a completed request still succeeds after its requested expiry has passed.

RDP membership detection checks live state only. It can legitimately detect the desired state before installation has ever run. Required assignment can reapply configured additions/removals if later drift occurs.

## Logging and reports

Both scripts append to `C:\CompanyIT\<PackageName>.log` by default:

```text
2026-09-24 10:00:00 - ========== Install Started ==========
2026-09-24 10:00:01 - Report saved: ...
2026-09-24 10:00:02 - ========== Install Completed Successfully ==========
```

Set `LogFolder` to your usual administrator-controlled log directory in both copies. Existing log contents are preserved. Account names, SIDs and errors can appear in local logs; manage permissions and retention. No passwords are accessed, changed or logged. Only successful detection writes a short result to stdout, as required by Intune custom detection. Installers and failed detection use the log and exit codes. Write-Output sends data to the calling process; it does not open a PowerShell window. These apps run under IME in System context without an interactive UI.

Reports and successful-run receipts are stored in `%ProgramData%\WindowsAdminManagement\Win32\<PackageName>\`. Installers restrict the state directory to SYSTEM and Administrators and reject reparse-point paths. Receipts bind the package version/configuration to the saved report. They are operational state, not protection against a malicious local administrator. Detection logs activity but does not create a successful receipt, change membership or modify a task.

The change-report package retains dated comparison files and advances `Baseline.json` only after writing the comparison. First run establishes the baseline with no claimed changes. Reports observe snapshots, not every intervening event or the actor who changed membership. Retention is administrator-managed; these scripts do not upload or automatically purge reports.

## Temporary-grant compatibility and policy alignment

Temporary checks, extensions and revocation understand the existing `scripts/TemporaryAdmin/Grant-TemporaryLocalAdmin.ps1` task format: one enabled daily SYSTEM task with the SID in its name/action, an enabled missed-run setting and a valid expiry. They inspect rather than execute the encoded action. Unknown, disabled or modified task formats are reported/refused; arbitrary tasks are not adopted or rewritten. This is a structural check, not tamper-proof enforcement.

ApprovedAdministratorCheck allows valid temporary direct Entra grants by default. Approved permanent member SIDs still need to be listed, including the built-in Administrator if your policy permits it. TemporaryAccessCheck separately exempts its configured permanent Entra administrator SIDs. Keep these policies consistent.

The original cleanup scripts remain unchanged and do not automatically consume these new reports or task exceptions. Avoid overlapping cleanup assignments that remove approved temporary users, or configure their documented SID exclusions for the approved period. Coordinate exception removal after expiry. These packages do not silently weaken an existing cleanup policy.

Group removal does not immediately revoke existing logon tokens. Arrange sign-out/sign-in where needed. Local administrators can modify tasks or create other access paths; temporary task-based membership is for trusted, approved use, not a security boundary against administrators. Direct membership checks do not expand nested groups or evaluate every source of effective privilege.

RDP membership alone does not enable Remote Desktop, configure its firewall/service, grant logon rights or override deny policies. Break-glass health does not test authentication or password availability. These limitations are deliberate so reporting does not unexpectedly change device security settings.

## Verification

Run the isolated suite:

```powershell
powershell.exe -NoProfile -File .\tests\Test-Win32Packages.ps1
```

The tests execute real report/receipt IO in disposable folders and simulate account, task and ACL mutations. They check success and failure paths, nonempty Win32 detection output, stale reports, altered configuration, current-state drift, temporary task validation, extension/revocation replay, and membership snapshot changes. They do not verify real Intune execution or Task Scheduler integration.

Pilot each configured app on a disposable managed device. Verify its SYSTEM context, logs, report/receipt permissions, before/after state, detection output and Intune post-install result. For one-time requests, rerun after expiry or after a later grant to confirm no action is repeated. Check existing cleanup assignments before testing temporary rights.

References: [Microsoft Win32 application and detection configuration](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32), [ScheduledTasks module](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/).
