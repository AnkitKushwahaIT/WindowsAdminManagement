# Contributing

Keep changes focused on the documented Entra cleanup or break-glass account workflows. Never commit a configured InitialPassword value. Describe any behavior change, update both standalone scripts when changing targeting or exclusions, and update documentation and tests together.

Run both `tests/Test-LocalAdminCleanup.ps1` and `tests/Test-LocalAdminAccount.ps1` with Windows PowerShell on Windows. Test real integration changes on a disposable, managed pilot device. Never execute cleanup on a shared development computer just to test it.

Use synthetic account data. Do not attach tenant exports, real SIDs, device logs, credentials, or personal information to public issues or pull requests. Keep PowerShell files compatible with Windows PowerShell 5.1 and encoded as UTF-8.
