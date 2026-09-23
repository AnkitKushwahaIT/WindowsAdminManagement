# ============================================================
# Windows - Detect Local Administrator
# Account : LocalAdmin
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

$AdminUser = "LocalAdmin"

$user = Get-LocalUser `
    -Name $AdminUser `
    -ErrorAction SilentlyContinue

$member = Get-LocalGroupMember `
    -Group "Administrators" `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq "$env:COMPUTERNAME\$AdminUser"
    }

if ($user -and $user.Enabled -and $member) {
    Write-Output "$AdminUser exists and is a local administrator."
    exit 0
}

exit 1
