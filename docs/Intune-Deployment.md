# Intune deployment

Use the two scripts together with the same exclusions. Validate on a pilot group before broad assignment.

## Recurring Remediations

| Setting | Value |
| --- | --- |
| Detection | `scripts/Detect-LocalAdminCleanup.ps1` |
| Remediation | `scripts/Invoke-LocalAdminCleanup.ps1` |
| Run using logged-on credentials | No (SYSTEM) |
| Run in 64-bit PowerShell | Yes |
| Signature check | No for these unsigned files, or sign and deploy trust before enabling |
| Schedule | Your required interval; daily is a starting point |

Check [Microsoft's current prerequisites and licensing](https://learn.microsoft.com/en-us/intune/device-management/tools/deploy-remediations).

Before uploading, edit `ExcludedMemberSids` defaults in **both deployment copies** if exceptions are required. Remediations uses the defaults in the uploaded scripts; the manual command-line examples do not configure those uploads. Use UTF-8 encoding. Neither script needs a companion file.

Detection exits 1 only when targeted members are found, which requests remediation. Exit 2 means evaluation failed; investigate it rather than interpreting it as compliance. Cleanup checks membership again and returns failure when targets remain or any removal fails. View Intune post-remediation detection and the local log.

## Optional Win32 app packaging

Package the cleanup script as a System-context Win32 app. Use this install command from the Intune 32-bit process on a 64-bit client:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-LocalAdminCleanup.ps1
```

Use `Detect-LocalAdminCleanup.ps1` as a custom detection script, with **Run script as 32-bit process on 64-bit clients: No**. Exit 0 plus its nonempty standard output indicates the cleanup condition is satisfied. No file marker is required. Match exclusions in the packaged cleanup and uploaded detection script. An already compliant device is detected without running cleanup.

This is a state-changing script, not a conventional installed application. Removing its assignment does not restore removed memberships. Do not advertise an automatic uninstall; use the recovery procedure below. Prefer Remediations for explicitly scheduled enforcement.

## Pilot checklist

1. Confirm an approved recovery administrator works and its password is retrievable if managed by LAPS.
2. Run cleanup manually with `-WhatIf`; review each intended removal and exclusion.
3. Apply on a pilot device, then run detection and check the log.
4. Verify affected employees can sign in as standard users after sign-out/sign-in and that required support access remains available.
5. Check for other policies that re-add direct users. Periodic cleanup does not prevent membership changes between runs.
6. Expand assignment after reviewing results.

For rollback, suspend the assignment and use an approved administrator to restore explicitly approved memberships from the removal log. No automatic rollback occurs after partial failure.

References: [Intune Remediations](https://learn.microsoft.com/en-us/intune/device-management/tools/deploy-remediations), [Win32 detection](https://learn.microsoft.com/en-us/intune/intune-service/apps/apps-win32-add), [LocalAccounts module](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/get-localgroupmember?view=powershell-5.1).
