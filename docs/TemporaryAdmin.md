# Temporary local administrator access

`Grant-TemporaryLocalAdmin.ps1` grants direct local administrator membership to the single Microsoft Entra user identified through Explorer process ownership, then schedules removal after a configurable number of days.

## Configuration

Edit the simple configuration section at the top:

```powershell
$DaysToKeep = 5
$LogFolder = 'C:\CompanyIT'
```

The script appends timestamped messages to `TempAdmin.log`. Use an administrator-controlled local directory. No account password is requested or modified.

## Run

Run in elevated 64-bit Windows PowerShell 5.1 or as SYSTEM while the intended user is signed in:

```powershell
.\scripts\TemporaryAdmin\Grant-TemporaryLocalAdmin.ps1
```

The script requires exactly one distinct Explorer process owner and an `AzureAD\` username. It reads that process owner's Entra SID and uses the SID for group changes and the removal task. It stops if no user is found, a local/domain user is found, or multiple different Explorer owners are present. Disconnected sessions with Explorer can cause this check to stop; the script does not guess which session you intended. A user without Explorer running is not supported.

Existing direct administrators are left unchanged; their original access is not scheduled for removal. An existing temporary removal task causes exit 1 without extending or replacing it. Review the pending task rather than repeatedly granting access.

## Expiry and verification

The SYSTEM removal task is registered **before** membership is added. Its name is `TempAdminRemoval_<user SID>`. It first runs at the expiry date/time, attempts missed runs when the device is available, and permits running on battery power. Failed runs retry three times at 15-minute intervals; a daily trigger remains until successful cleanup.

Removal verifies the SID is absent before logging success and deleting the task. On failure the task remains for retries. The encoded command preserves quoting; encoding is not encryption and does not conceal a secret.

If granting membership fails after task registration, the removal task is retained. If verification or logging fails after granting access, the script reports failure and the scheduled removal remains. It does not automatically undo earlier successful changes.

Exit 0 means the grant was verified or the user was already a direct administrator and no action was needed. Exit 1 means the operation could not complete, including an existing temporary task. Check the log to distinguish outcomes.

## Operational limits

- A user needs a new sign-in session to obtain updated privileges. Removing group membership does not terminate existing sessions or revoke already-issued administrator tokens. Arrange sign-out/sign-in at expiry when appropriate.
- Local administrators can tamper with scheduled tasks or create another administrator. This is an operational convenience for trusted users, not tamper-proof time-limited elevation.
- The script changes direct local membership only. It does not remove access inherited through groups or Entra roles.
- No device can execute a scheduled removal while powered off. Removal occurs when Windows and Task Scheduler can run it; review failed tasks and logs.
- Other policies, including this repository's Entra cleanup script, can remove the temporary membership earlier. Coordinate assignments/exclusions.
- Use an explicitly approved, one-time grant. Do not assign this as a recurring grant remediation or a required app that automatically grants again after expiry. Running it after a completed removal starts a new grant period. No automatic-renewal detection rule is included.

If using Intune for a one-time approved execution, use SYSTEM and 64-bit PowerShell. Ensure the intended user is signed in when it runs. This script is separate from the original creation/detection/uninstall scripts and does not replace them.

## Pilot tests

On a disposable managed device, confirm the intended user and SID, the new direct membership, the SYSTEM task, its expiry and settings, and the log. For a short expiry test, change the `AddDays($DaysToKeep)` expression to `AddMinutes(5)` in a private test copy. Test removal, an offline-at-expiry scenario, and a simulated removal failure. Verify existing administrators are not targeted.

`tests/Test-TemporaryAdmin.ps1` runs isolated mocked checks for grant and removal behavior. It does not change real accounts or tasks and does not replace a Windows Task Scheduler pilot.

Microsoft references: [scheduled task settings](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset), [scheduled task triggers](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasktrigger).
