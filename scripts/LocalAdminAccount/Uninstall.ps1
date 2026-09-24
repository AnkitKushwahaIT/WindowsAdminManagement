#requires -Version 5.1
<#
.SYNOPSIS
Deletes only a local account whose SID matches this package's ownership record.
.DESCRIPTION
Requires explicit -ConfirmRemoval after independently verifying another recovery
administrator. Does not delete profiles. Supports -WhatIf. Exit 1 on failure.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_-]{0,19}$')]
    [string]$UserName = 'ManagedLocalAdmin',
    [switch]$ConfirmRemoval,
    [string]$LogFolder = (Join-Path $env:ProgramData 'WindowsAdminManagement')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$AppName = 'Managed Local Admin'
$version = '1.0.0'
$LogFile = Join-Path $LogFolder 'approvedapps.log'
$logReady = $false

function Write-Log {
    param([string]$Message)
    if ($WhatIfPreference) { return }
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $AppName $version - $Message" |
        Out-File -LiteralPath $LogFile -Append -Encoding UTF8 -ErrorAction Stop
}

$registryPath = "HKLM:\SOFTWARE\WindowsAdminManagement\LocalAdminAccounts\$UserName"
try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell.' }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run elevated or as SYSTEM.' }
    if (-not $WhatIfPreference) {
        New-Item -Path $LogFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $logReady = $true
    }
    Write-Log '========== Uninstall Started =========='
    Write-Log "Target account: $UserName"
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
    $users = @(Get-LocalUser -ErrorAction Stop)
    $namedUser = @($users | Where-Object { $_.Name -eq $UserName })
    if (-not (Test-Path -LiteralPath $registryPath)) {
        if ($namedUser.Count) { throw 'Account exists without package ownership; refusing deletion.' }
        Write-Log 'Already absent: no account or package record.'
        Write-Output 'Already absent: no account or package record.'
        exit 0
    }
    $record = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
    $sid = [Security.Principal.SecurityIdentifier]::new($record.AccountSid).Value
    if ($sid -match '-500$') { throw 'Refusing to delete the built-in Administrator.' }
    $ownedUser = @($users | Where-Object { $_.SID.Value -eq $sid })
    if ($namedUser.Count -and $namedUser[0].SID.Value -ne $sid) { throw 'Account name now belongs to a different SID; refusing deletion.' }
    if ($ownedUser.Count -and $ownedUser[0].Name -ne $UserName) { throw 'Owned account was renamed; investigate before deletion.' }
    if (-not $ConfirmRemoval -and -not $WhatIfPreference) { throw 'Specify -ConfirmRemoval only after verifying an independent recovery administrator.' }
    if (-not $PSCmdlet.ShouldProcess("$UserName [$sid]", 'Delete package-owned account and ownership record')) { exit 0 }
    if ($ownedUser.Count) {
        Write-Log 'Removing verified package-owned account.'
        Remove-LocalUser -SID $sid -ErrorAction Stop
    }
    if (@(Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID.Value -eq $sid }).Count) { throw 'Account remains after removal.' }
    # Remove only this account's non-recursive registry record.
    Remove-Item -LiteralPath $registryPath -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $registryPath) { throw 'Ownership record remains after removal.' }
    Write-Log 'Account removal verified. Registry record removed.'
    Write-Log '========== Uninstall Completed Successfully =========='
    Write-Output "Uninstalled: $UserName account and package record are absent."
    exit 0
}
catch {
    $failure = $_.Exception.Message
    if ($logReady) {
        try { Write-Log "ERROR: $failure" }
        catch { Write-Output 'Unable to write the error to the log file.' }
    }
    Write-Output "Uninstall failed: $failure"
    exit 1
}
