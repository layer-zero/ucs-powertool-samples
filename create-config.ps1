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

$mgmt_vlan = 101
$vmotion_vlan = 102
$iscsi_a_vlan = 103
$iscsi_b_vlan = 104
$nfs_vlan = 105

$dynamic_vlan_start = 1001
$dynamic_vlan_end = 1200

# Connect to UCS Manager using a session xml file and a secure key defined in a key file
$key = ConvertTo-SecureString (Get-Content .\ucs.key)
$handle = Connect-Ucs -Key $key -LiteralPath .\ucs.xml

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

# Create static infrastructure VLANs 
Get-UcsLanCloud | Add-UcsVlan -Id $mgmt_vlan -Name $mgmt_vlan"_mgmt_dc"$site_id -DefaultNet "no" -ModifyPresent
Get-UcsLanCloud | Add-UcsVlan -Id $vmotion_vlan -Name $vmotion_vlan"_vmotion_dc"$site_id -DefaultNet "no" -ModifyPresent
Get-UcsLanCloud | Add-UcsVlan -Id $iscsi_a_vlan -Name $iscsi_a_vlan"_iscsi_a_dc"$site_id -DefaultNet "no" -ModifyPresent
Get-UcsLanCloud | Add-UcsVlan -Id $iscsi_b_vlan -Name $iscsi_b_vlan"_iscsi_b_dc"$site_id -DefaultNet "no" -ModifyPresent
Get-UcsLanCloud | Add-UcsVlan -Id $nfs_vlan -Name $nfs_vlan"_nfs_dc"$site_id -DefaultNet "no" -ModifyPresent

# Create dynamic VLANs for VMs
# To save time during reruns of the script, we check for existence of the VLAN instead of using the -ModifyPresent switch
$mo = Get-UcsLanCloud 
for ($i=$dynamic_vlan_start;$i -le $dynamic_vlan_end; $i++) {
    $vlan = Get-UcsVlan -Name "vm_dynamic_$i"
    if (-Not $vlan) {
        $mo | Add-UcsVlan -Id $i -Name "vm_dynamic_$i" -DefaultNet "no"
    }
}

# Disconnect from UCS Manager
Disconnect-Ucs -Ucs $handle
