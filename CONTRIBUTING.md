# Contributing

Keep changes focused on direct Entra user membership cleanup. Describe any behavior change, update both standalone scripts when changing targeting or exclusions, and update documentation and tests together.

Run `powershell.exe -NoProfile -File .\tests\Test-LocalAdminCleanup.ps1` on Windows. Test real integration changes on a disposable, managed pilot device. Never execute cleanup on a shared development computer just to test it.

Use synthetic account data. Do not attach tenant exports, real SIDs, device logs, credentials, or personal information to public issues or pull requests. Keep PowerShell files compatible with Windows PowerShell 5.1 and encoded as UTF-8.
