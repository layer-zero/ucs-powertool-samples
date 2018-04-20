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
$vlan_names = $mo | Get-UcsManagedObject -ClassId fabricVlan | Select Name | Out-String -Stream
for ($i=$dynamic_vlan_start;$i -le $dynamic_vlan_end; $i++) {
    $vlan_exists = $vlan_names.Contains("vm_dynamic_$i")
    if (-Not $vlan_exists) {
        $mo | Add-UcsVlan -Id $i -Name "vm_dynamic_$i" -DefaultNet "no"
    }
}

# Set MTU to Jumbo frames (9216 bytes) for Best-Effort QoS class 
Get-UcsBestEffortQosClass | Set-UcsBestEffortQosClass -Mtu "9216" -Force

# Set power control policy to grid redundancy
Get-UcsPowerControlPolicy | Set-UcsPowerControlPolicy -Redundancy "grid" -Force

# Set chassis discovery policy to 1-link and port-channel
Get-UcsChassisDiscoveryPolicy | Set-UcsChassisDiscoveryPolicy -Action "1-link" -LinkAggregationPref "port-channel" -Force

# Create BIOS policy for ESXi hosts
# Based on recommendations from https://datacenterdennis.wordpress.com/2016/12/09/cisco-ucs-bios-policy-recommendations/
$mo = Get-UcsOrg -Level root | Add-UcsBiosPolicy -Descr "BIOS policy for generic ESXi hosts" -Name "esxi_bios" -RebootOnUpdate yes -ModifyPresent
$mo | Set-UcsBiosVfSerialPortAEnable -VpSerialPortAEnable disabled -Force
$mo | Set-UcsBiosVfQuietBoot -VpQuietBoot disabled -Force
$mo | Set-UcsBiosVfPOSTErrorPause -VpPOSTErrorPause disabled -Force
$mo | Set-UcsBiosVfFrontPanelLockout -VpFrontPanelLockout disabled -Force
$mo | Set-UcsBiosVfConsistentDeviceNameControl -VpCDNControl disabled -Force
$mo | Set-UcsBiosVfResumeOnACPowerLoss -VpResumeOnACPowerLoss last-state -Force
$mo | Set-UcsBiosVfQPILinkFrequencySelect -VpQPILinkFrequencySelect auto -Force
$mo | Set-UcsBiosVfQPISnoopMode -VpQPISnoopMode home-snoop -Force
$mo | Set-UcsBiosVfTrustedPlatformModule -VpTrustedPlatformModuleSupport enabled -Force
$mo | Set-UcsBiosVfIntelTrustedExecutionTechnology -VpIntelTrustedExecutionTechnologySupport enabled -Force
$mo | Set-UcsBiosExecuteDisabledBit -VpExecuteDisableBit enabled -Force
$mo | Set-UcsBiosVfDirectCacheAccess -VpDirectCacheAccess enabled -Force
$mo | Set-UcsBiosVfLocalX2Apic -VpLocalX2Apic auto -Force
$mo | Set-UcsBiosVfFrequencyFloorOverride -VpFrequencyFloorOverride enabled -Force
$mo | Set-UcsBiosVfDRAMClockThrottling -VpDRAMClockThrottling auto -Force
$mo | Set-UcsBiosVfInterleaveConfiguration -VpChannelInterleaving auto -VpRankInterleaving auto -Force
$mo | Set-UcsBiosVfAltitude -VpAltitude auto -Force
$mo | Set-UcsBiosTurboBoost -VpIntelTurboBoostTech enabled -Force
$mo | Set-UcsBiosEnhancedIntelSpeedStep -VpEnhancedIntelSpeedStepTech enabled -Force
$mo | Set-UcsBiosHyperThreading -VpIntelHyperThreadingTech enabled -Force
$mo | Set-UcsBiosVfCoreMultiProcessing -VpCoreMultiProcessing all -Force
$mo | Set-UcsBiosVfIntelVirtualizationTechnology -VpIntelVirtualizationTechnology enabled -Force
$mo | Set-UcsBiosVfProcessorEnergyConfiguration -VpEnergyPerformance performance -VpPowerTechnology performance -Force
$mo | Set-UcsBiosVfProcessorCState -VpProcessorCState enabled -Force
$mo | Set-UcsBiosVfProcessorC1E -VpProcessorC1E enabled -Force
$mo | Set-UcsBiosVfCPUPerformance -VpCPUPerformance enterprise -Force
$mo | Set-UcsBiosVfPackageCStateLimit -VpPackageCStateLimit c1 -Force
$mo | Set-UcsBiosVfProcessorC3Report -VpProcessorC3Report disabled -Force
$mo | Set-UcsBiosVfProcessorC6Report -VpProcessorC6Report disabled -Force
$mo | Set-UcsBiosVfProcessorC7Report -VpProcessorC7Report disabled -Force
$mo | Set-UcsBiosVfMaxVariableMTRRSetting -VpProcessorMtrr auto-max -Force
$mo | Set-UcsBiosVfScrubPolicies -VpDemandScrub enabled -VpPatrolScrub enabled -Force
$mo | Set-UcsBiosIntelDirectedIO -VpIntelVTForDirectedIO enabled -Force
$mo | Set-UcsBiosNUMA -VpNUMAOptimized enabled -Force
$mo | Set-UcsBiosLvDdrMode -VpLvDDRMode performance-mode -Force
$mo | Set-UcsBiosVfDramRefreshRate -VpDramRefreshRate auto -Force
$mo | Set-UcsBiosVfSelectMemoryRASConfiguration -VpSelectMemoryRASConfiguration maximum-performance -Force
$mo | Set-UcsBiosVfDDR3VoltageSelection -VpDDR3VoltageSelection ddr3-1350mv -Force
$mo | Set-UcsBiosVfConsoleRedirection -VpConsoleRedirection disabled -Force

# Disconnect from UCS Manager
Disconnect-Ucs -Ucs $handle
