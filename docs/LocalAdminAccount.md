# Break-glass local administrator

These three scripts create, detect and uninstall a dedicated local break-glass administrator. They are separate from the Entra user cleanup scripts.

## Configure before packaging

1. Make a private copy of `scripts/LocalAdminAccount`.
2. Set the `UserName` default in **all three scripts** to your chosen account name. The default is `ManagedLocalAdmin`.
3. In `AdminCreation.ps1`, fill in the clearly marked configuration field:

```powershell
$InitialPassword = '' # Enter your chosen password inside these quotes in your private copy.
```

4. Save and test your private scripts before packaging.

The public password field is intentionally blank. First-time creation fails until an admin fills it in. Use a single-quoted PowerShell string; represent an apostrophe inside the password with two apostrophes. Do not commit your configured copy to GitHub. The password is readable in the configured script and package, so restrict access to those deployment files. Converting it to SecureString does not encrypt the source file.

**No password rotation:** the password is used only when creating the account. New accounts have non-expiring passwords. Repeated installation repairs enabled state and administrator membership without resetting the password. These scripts do not configure LAPS or change the expiration setting on subsequent runs. Store the credential securely and verify that it works as your recovery method.

## Files

| File | Purpose |
| --- | --- |
| `AdminCreation.ps1` | Create or repair a package-owned local administrator |
| `Detection.ps1` | Verify version, account SID, enabled state and administrator membership |
| `Uninstall.ps1` | Remove only the exact account created by this package |

Run in elevated 64-bit Windows PowerShell 5.1, or SYSTEM. Account names support 1-20 letters, digits, underscores and hyphens, starting with a letter. The Administrators group is addressed by SID, independent of display language.

## Intune Win32 deployment

Package your configured `AdminCreation.ps1` and `Uninstall.ps1` with the Microsoft Win32 Content Prep Tool. Upload your configured `Detection.ps1` separately as the custom detection script.

Install command:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\AdminCreation.ps1
```

| Setting | Value |
| --- | --- |
| Install behavior | System |
| Requirements | Your piloted 64-bit Windows versions |
| Custom detection | `Detection.ps1` with matching UserName default |
| Run detection as 32-bit on 64-bit clients | No |
| Return codes | 0 = Success; 1 = Failed |
| Signature check | No for unsigned files, or sign and deploy certificate trust first |
| Assignment | Required to a pilot group first |
| Allow available uninstall | No |

Detection returns 0 **with stdout** only when the expected version, exact SID, enabled state and direct administrator membership all match. A registry key alone is not enough. All other results return 1.

Uninstall command, with 64-bit PowerShell selected inside the command because Intune does not directly expand environment variables in its uninstall field:

```text
cmd.exe /c ""%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Uninstall.ps1 -ConfirmRemoval"
```

Use an Uninstall assignment only after verifying another recovery administrator. Removing a Required assignment does not delete the account. Preview manually with `Uninstall.ps1 -WhatIf`. Neither script forces a reboot or deletes the user profile.

## Logging

Creation and uninstall append to `%ProgramData%\WindowsAdminManagement\approvedapps.log`, preserving this format:

```text
2026-01-01 10:00:00 - Managed Local Admin 1.0.0 - Installation Started
```

Entries record start, target account, creation or reuse, group membership, verification, registry updates, completion and errors. Passwords are not intentionally logged. Use `-LogFolder "C:\CompanyIT"` on creation and uninstall to choose an administrator-controlled directory. Appending preserves earlier entries; the scripts do not rotate or overwrite the log. Manage log access and retention separately.

`Write-Output` supplies a brief Intune status in addition to file logging. Detection remains read-only and writes its required result to stdout; it does not create a log file. `-WhatIf` does not write log files. Logging failures return exit 1; changes completed before a later log failure are not rolled back.

## Ownership and errors

Account SID and version are recorded under `HKLM:\SOFTWARE\WindowsAdminManagement\LocalAdminAccounts\<UserName>`. No password is written to the registry or script status output. Local administrators can modify these records; ownership checks are safeguards against mistakes, not a security boundary against administrators.

An existing account without the matching ownership record is refused. Older internal accounts are not automatically adopted. Reinstallation never changes an existing account's password, even if the configured InitialPassword has changed.

Creation initially creates the account disabled, records its SID, adds administrator membership, enables it and verifies it before writing the version. Earlier changes are not automatically rolled back after a failure. If ownership recording fails, a disabled unowned account may remain and requires manual review. A stale ownership record for an absent account must be reviewed and cleared through uninstall before recreation.

Uninstall verifies SID ownership, refuses renamed/replaced accounts and the built-in Administrator, verifies deletion, and then removes the account's registry record. It reports failures rather than suppressing them. `-ConfirmRemoval` expresses your intent; the script does not test whether another usable recovery account exists.

## Pilot checks

Test creation, repeat installation, disabled-account repair, missing-membership repair and live detection. Confirm the password stays unchanged on repeat installation. Test uninstall only on a disposable device with another verified administrator.

Run `powershell.exe -NoProfile -File .\tests\Test-LocalAdminAccount.ps1` from the repository root for isolated simulated checks. These do not replace device testing.

References: [New-LocalUser](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/new-localuser?view=powershell-5.1), [Intune Win32 app configuration](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32).
