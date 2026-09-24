$ErrorActionPreference = "Stop"

$UserName = "LocalAdmin"
$RegistryPath = "HKLM:\SOFTWARE\CompanyIT\LocalAdmin"

try {

    # Registry
    if (!(Test-Path $RegistryPath)) {
        exit 1
    }

    # User
    $User = Get-LocalUser -Name $UserName -ErrorAction Stop

    if (!$User.Enabled) {
        exit 1
    }

    exit 0

}
catch {

    exit 1

}