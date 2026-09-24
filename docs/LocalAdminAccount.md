# Local administrator scripts

These are the original creation, detection and uninstall scripts with only company-specific names, paths and the password removed or generalized. Their logic and logging structure are unchanged.

## Configure your private copy

- Set `$UserName` in all three scripts to your chosen local account name. The public default is `LocalAdmin`.
- Enter your password in the empty quoted value passed to `ConvertTo-SecureString` in `AdminCreation.ps1`. Do this before running or packaging; the blank public value is not executable configuration. Never commit the configured password to the public repository.
- Change the company-neutral paths if needed: `C:\CompanyIT` and `HKLM:\SOFTWARE\CompanyIT\LocalAdmin`.
- The original creation log appends to `C:\CompanyIT\approvedapps.log` using timestamp, application name, version and message.

## Original behavior retained

`AdminCreation.ps1` creates the account if absent, or sets its password to the configured value if it already exists. Newly created accounts have non-expiring passwords. It adds administrator membership, enables the account and writes the version registry value. There is no scheduled password rotation or LAPS configuration.

`Detection.ps1` checks that the registry path exists and the account is enabled. It returns an exit code only. It does not check administrator membership or write success output; Intune Win32 custom detection requires success output as well as exit 0, so this unchanged detection is not a validated Win32 detection rule.

`Uninstall.ps1` removes the named account and registry path, suppresses errors and exits 0, as in the original.

No extra ownership safeguards, runtime password inputs, preview switches or logging rewrites have been added. The original broad catch around group addition and uninstall error suppression are retained. Review and test these original behaviors before deployment. Automated checks parse syntax only; they do not execute account changes or certify the scripts for production.
