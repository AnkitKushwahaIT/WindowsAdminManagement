$UserName = "LocalAdmin"

Remove-LocalUser -Name $UserName -ErrorAction SilentlyContinue

Remove-Item `
    "HKLM:\SOFTWARE\CompanyIT\LocalAdmin" `
    -Force `
    -Recurse `
    -ErrorAction SilentlyContinue

exit 0