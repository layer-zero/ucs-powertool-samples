# Create a full sample UCS configuration from scratch using PowerShell

# Import UCS Powertool Module
Import-Module Cisco.UCSManager

# Declare global variables
$site_id = 1
$pod_id = 1

$environments = @("prd", "acc", "tst", "dev")

$hostname_prefix = "ucspe-"

$ip_prefix = "192.168.218"
$ip_mask = "255.255.255.0"
$ip_pool_size = 100

# Connect to UCS Manager using a session xml file and a secure key defined in a key file
$key = ConvertTo-SecureString (Get-Content .\ucs.key)
$handle = Connect-Ucs -Key $key -LiteralPath .\ucs$handle1 = Connect-Ucs -Name.xml

# Set UCS system name
# This uses the generic Set-UcsManagedObject method, because no specific cmdlet exists
$hostname = $hostname_prefix + $site_id + $pod_id
Get-UcsManagedObject -Dn sys | Set-UcsManagedObject -PropertyMap @{name = $hostname} -Force

# Create suborganizations
foreach ($env in $environments) {
    Get-UcsOrg -Level root | Add-UcsOrg $env -ModifyPresent
}

# Assign IP block to ext-mgmt pool and set order to sequential
$first_host = $ip_pool_size + 1
$last_host = $first_host + $ip_pool_size - 1
$first_ip = $ip_prefix+"."+$first_host
$last_ip = $ip_prefix+"."+$last_host
$mo = Get-UcsOrg -Level root | Get-UcsIpPool -Name "ext-mgmt"
$mo | Set-UcsIpPool -AssignmentOrder sequential -Force
$mo | Add-UcsIpPoolBlock -DefGw "$ip_prefix.254" -From $first_ip -To $last_ip -Subnet $ip_mask -ModifyPresent

# Create management IP pools for each environment
$sub_pool_size = [int]($ip_pool_size/$environments.Length)
$n = 0
foreach ($env in $environments) {
    $first_host = 1 + $n * $sub_pool_size
    $last_host = $first_host + $sub_pool_size - 1
    $first_ip = $ip_prefix+"."+$first_host
    $last_ip = $ip_prefix+"."+$last_host
    $pool_name =  $env+"_kvm_ip_dc"+$site_id
    $mo = Get-UcsOrg -name $env  | Add-UcsIpPool -AssignmentOrder "sequential" -Descr "IP pool for $env service profiles" -Name $pool_name -ModifyPresent
    $mo | Add-UcsIpPoolBlock -DefGw "$ip_prefix.254" -From $first_ip -To $last_ip -Subnet $ip_mask -ModifyPresent
    $n = $n + 1
}

# Disconnect from UCS Manager
Disconnect-Ucs -Ucs $handle
