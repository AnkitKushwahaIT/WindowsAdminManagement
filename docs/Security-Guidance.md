# Security and scope

## Access policy

The scripts remove only direct `AzureAD\` entries classified as users. They retain local users (including LAPS accounts), domain entries, groups and unresolved entries. Exclusions use exact SIDs, not username substrings. An empty exclusion list means every matching direct Entra user is targeted, including a support administrator listed that way.

The scripts do not verify recovery accounts or LAPS password escrow. Confirm a separate recovery path before deployment. They do not identify the purpose of retained Entra SIDs, expand group membership, or evaluate effective privileges. Users may retain administrative access through Entra roles or other groups. See [Microsoft's Entra local administrator guidance](https://learn.microsoft.com/en-us/entra/identity/devices/assign-local-admin).

Removing membership does not revoke existing logon tokens immediately. Have affected users sign out and back in. The scripts do not deny logon, terminate sessions, or delete profiles.

## Failure and recovery

Membership read errors abort processing. Removal failures are counted and produce a nonzero exit; subsequent targets may still be processed. Verification errors and log-write errors also produce failure. Successful changes before an error are not rolled back.

Keep an approved administrator available to restore selected memberships using the local log. Stop recurring assignment first if restoring a member that the policy would remove again. Unassigning the scripts does not undo changes.

## Public repository and logs

Do not commit production passwords, tenant identifiers, user SIDs, exported device inventories, device logs, certificates, or private keys. Use synthetic values in examples and redact issue attachments. Detailed local logs contain account names and SIDs; restrict access and manage retention according to organizational policy. The script does not upload logs and does not rotate them automatically. Windows error messages included in status output may also contain account identifiers.

The default log location is under ProgramData. If overriding it, use an administrator-controlled local directory. Do not run cleanup concurrently from multiple management systems.

Historical versions are retained in Git history. Removing old files from the current branch does not erase them from earlier commits. Never treat a committed real credential as safe because a file was later removed; revoke it and handle history separately.
