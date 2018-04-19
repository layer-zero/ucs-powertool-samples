# Create a full sample UCS configuration from scratch using PowerShell

# Import UCS Powertool Module
Import-Module Cisco.UCSManager

# Declare global variables
$site_id = 1
$pod_id = 1

$environments = @("dev", "tst", "acc", "prd")

$hostname_prefix = "ucspe-"

# Connect to UCS Manager using a session xml file and a secure key defined in a key file
$key = ConvertTo-SecureString (Get-Content .\ucspe.key)
$handle = Connect-Ucs -Key $key -LiteralPath .\ucspe.xml

# Set UCS system name
# This uses the generic Set-UcsManagedObject method, because no specific cmdlet exists
$hostname = $hostname_prefix + $site_id + $pod_id
Get-UcsManagedObject -Dn sys | Set-UcsManagedObject -PropertyMap @{name = $hostname} -Force

# Create suborganizations
foreach ($env in $environments) {
    Get-UcsOrg -Level root | Add-UcsOrg $env -ModifyPresent
}

# Disconnect from UCS Manager
Disconnect-Ucs -Ucs $handle
