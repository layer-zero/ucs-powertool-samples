# Create a full sample UCS configuration from scratch using PowerShell

# Import UCS Powertool Module
Import-Module Cisco.UCSManager

# Declare global variables
$site_id = 1
$pod_id = 1

$environments = @("prd", "acc", "tst", "dev")

$fabrics = @("A", "B")

$hostname_prefix = "ucspe-"

$ip_prefix = "192.168"
$mgmt_block = "218"
$iscsi_blocks = @{A = "103" 
                  B = "104"}

$ip_mask = "255.255.255.0"
# For the IP host range used for pools is from $ip_offset to $ip_offset + 2 * ip_pool_size
# The FI and cluster addresses should fall outside this range 
$ip_pool_size = 100
$ip_offset = 50

$mgmt_vlan = 101
$vmotion_vlan = 102
$iscsi_a_vlan = 103
$iscsi_b_vlan = 104
$nfs_vlan = 105

$dynamic_vlan_start = 1001
$dynamic_vlan_end = 1200

$target_iqn = "iqn.1992-08.com.netapp:sn.123456789"
$target_host = "250"

# Connect to UCS Manager using a session xml file and a secure key defined in a key file
$key = ConvertTo-SecureString (Get-Content .\ucs.key)
$handle = Connect-Ucs -Key $key -LiteralPath .\ucs.xml

# Set UCS system name
$hostname = $hostname_prefix + $site_id + $pod_id
Get-UcsTopSystem | Set-UcsTopSystem -Name $hostname -Force

# Create suborganizations
foreach ($env in $environments) {
    Get-UcsOrg -Level root | Add-UcsOrg $env -ModifyPresent
}

# Assign IP block to ext-mgmt pool and set order to sequential
$first_host = $ip_offset + $ip_pool_size + 1
$last_host = $first_host + $ip_pool_size - 1
$first_ip = $ip_prefix+"."+$mgmt_block+"."+$first_host
$last_ip = $ip_prefix+"."+$mgmt_block+"."+$last_host
$gateway = $ip_prefix+"."+$mgmt_block+".254"
$mo = Get-UcsOrg -Level root | Get-UcsIpPool -Name "ext-mgmt"
$mo | Set-UcsIpPool -AssignmentOrder sequential -Force
$mo | Add-UcsIpPoolBlock -DefGw $gateway -From $first_ip -To $last_ip -Subnet $ip_mask -ModifyPresent

# Create management IP pools for each environment
$sub_pool_size = [int]($ip_pool_size/$environments.Length)
$n = 0
foreach ($env in $environments) {
    $pool_name =  $env+"_kvm_ip_dc"+$site_id
    $first_host = $ip_offset + 1 + $n * $sub_pool_size
    $last_host = $first_host + $sub_pool_size - 1
    $first_ip = $ip_prefix+"."+$mgmt_block+"."+$first_host
    $last_ip = $ip_prefix+"."+$mgmt_block+"."+$last_host
    $gateway = $ip_prefix+"."+$mgmt_block+".254"
    $mo = Get-UcsOrg -name $env  | Add-UcsIpPool -Name $pool_name -AssignmentOrder "sequential" -Descr "IP pool for $env service profiles" -ModifyPresent
    $mo | Add-UcsIpPoolBlock -DefGw $gateway -From $first_ip -To $last_ip -Subnet $ip_mask -ModifyPresent
    $n = $n + 1
}

# Create mac address pools for fabric A and B
foreach ($fabric in $fabrics) {
    $pool_name = "esxi_mac_"+$fabric.ToLower()+"_dc"+$site_id
    $from_mac = "00:25:B5:"+$site_id+$pod_id+":"+$fabric+"0:00"
    $to_mac = "00:25:B5:"+$site_id+$pod_id+":"+$fabric+"1:FF"
    $mo = Get-UcsOrg -Level root  | Add-UcsMacPool -Name $pool_name -AssignmentOrder sequential -ModifyPresent
    $mo | Add-UcsMacMemberBlock -From $from_mac -To $to_mac -ModifyPresent
}

# Create iSCSI IP pools for each environment
$sub_pool_size = [int]($ip_pool_size/$environments.Length)
$n = 0
foreach ($env in $environments) {
    foreach ($fabric in $fabrics){
		$pool_name = $env+"_iscsi_ip_"+$fabric.ToLower()+"_dc"+$site_id
		$first_host = $ip_offset + 1 + $n * $sub_pool_size
		$last_host = $first_host + $sub_pool_size - 1
		$first_ip = $ip_prefix+"."+$iscsi_blocks[$fabric]+"."+$first_host
		$last_ip = $ip_prefix+"."+$iscsi_blocks[$fabric]+"."+$last_host
		$gateway = $ip_prefix+"."+$iscsi_blocks[$fabric]+".254"
		$mo = Get-UcsOrg -name $env  | Add-UcsIpPool -Name $pool_name -AssignmentOrder "sequential" -ModifyPresent
		$mo | Add-UcsIpPoolBlock -DefGw $gateway -From $first_ip -To $last_ip -Subnet $ip_mask -ModifyPresent
	}
	$n = $n + 1
}

# Create IQN pools for each environment
foreach ($env in $environments) {
    foreach ($fabric in $fabrics){
        $pool_name = $env+"_iqn_"+$fabric.ToLower()+"_dc"+$site_id
        $iqn_prefix = "iqn.1987-05.com.cisco"
        $iqn_suffix = "ucs-s"+$site_id+"p"+$pod_id+"-"+$env+"-"+$fabric.ToLower()
        $mo = Get-UcsOrg -name $env  | Add-UcsIqnPoolPool -Name $pool_name -AssignmentOrder "sequential" -Prefix $iqn_prefix -ModifyPresent
        $mo_1 = $mo | Add-UcsIqnPoolBlock -From 1 -Suffix $iqn_suffix -To 160 -ModifyPresent
    }
}

# Populate default UUID pool and set order to sequential
$first_suffix = "0"+$site_id+"0"+$pod_id+"-000000000001"
$last_suffix = "0"+$site_id+"0"+$pod_id+"-0000000000FF"
$mo = Get-UcsOrg -Level root | Get-UcsUuidSuffixPool -Name "default" -LimitScope
$mo | Set-UcsUuidSuffixPool -AssignmentOrder sequential -Force
$mo | Add-UcsUuidSuffixBlock -From $first_suffix -To $last_suffix -ModifyPresent

# Create static infrastructure VLANs 
Get-UcsLanCloud | Add-UcsVlan -Id $mgmt_vlan -Name $mgmt_vlan"_mgmt_dc"$site_id -DefaultNet no -ModifyPresent
Get-UcsLanCloud | Add-UcsVlan -Id $vmotion_vlan -Name $vmotion_vlan"_vmotion_dc"$site_id -DefaultNet no -ModifyPresent
Get-UcsLanCloud | Add-UcsVlan -Id $iscsi_a_vlan -Name $iscsi_a_vlan"_iscsi_a_dc"$site_id -DefaultNet no -ModifyPresent
Get-UcsLanCloud | Add-UcsVlan -Id $iscsi_b_vlan -Name $iscsi_b_vlan"_iscsi_b_dc"$site_id -DefaultNet no -ModifyPresent
Get-UcsLanCloud | Add-UcsVlan -Id $nfs_vlan -Name $nfs_vlan"_nfs_dc"$site_id -DefaultNet no -ModifyPresent

# Create dynamic VLANs for VMs
#
# To save time during reruns of the script, we check for existence of the VLAN instead of using the -ModifyPresent switch
$mo = Get-UcsLanCloud
$vlan_names = $mo | Get-UcsManagedObject -ClassId fabricVlan | Select Name | Out-String -Stream
for ($i=$dynamic_vlan_start;$i -le $dynamic_vlan_end; $i++) {
    $vlan_exists = $vlan_names.Contains("vm_dynamic_$i")
    if (-Not $vlan_exists) {
        $mo | Add-UcsVlan -Id $i -Name "vm_dynamic_$i" -DefaultNet no
    }
}

# Set MTU to Jumbo frames (9216 bytes) for Best-Effort QoS class 
Get-UcsBestEffortQosClass | Set-UcsBestEffortQosClass -Mtu 9216 -Force

# Set power control policy to grid redundancy
Get-UcsPowerControlPolicy | Set-UcsPowerControlPolicy -Redundancy grid -Force

# Set chassis discovery policy to 1-link and port-channel
Get-UcsChassisDiscoveryPolicy | Set-UcsChassisDiscoveryPolicy -Action 1-link -LinkAggregationPref port-channel -Force

# Create BIOS policy for ESXi hosts
#
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

# Create iSCSI boot policy
$mo = Get-UcsOrg -Level root | Add-UcsBootPolicy -Name "esxi_iscsi_boot" -BootMode legacy -EnforceVnicName yes -RebootOnUpdate no -Descr "Boot from iSCSI for ESXi hosts" -ModifyPresent
$mo | Add-UcsLsbootVirtualMedia -Access read-only -LunId 0 -Order 1 -ModifyPresent
$mo_1 = $mo | Add-UcsLsbootIScsi -Order 2 -ModifyPresent
$mo_1 | Add-UcsLsbootIScsiImagePath -ISCSIVnicName "iscsi_a" -Type primary -ModifyPresent
$mo_1 | Add-UcsLsbootIScsiImagePath -ISCSIVnicName "iscsi_b" -Type secondary -ModifyPresent

# Create local disk policy for diskless blades
Get-UcsOrg -Level root | Add-UcsLocalDiskConfigPolicy -Name "no_local_disk" -Mode no-local-storage -FlexFlashState disable -FlexFlashRAIDReportingState disable -ModifyPresent

# Create local disk policy using RAID-1 for servers with local hard disks or SSDs
Get-UcsOrg -Level root | Add-UcsLocalDiskConfigPolicy -Name "local_disk_raid1" -Mode raid-mirrored -ProtectConfig yes -FlexFlashState disable -FlexFlashRAIDReportingState disable -ModifyPresent

# Creat local disk policy that accepts any disk configuration
Get-UcsOrg -Level root | Add-UcsLocalDiskConfigPolicy -Name "accept_any" -Mode any-configuration -FlexFlashState disable -FlexFlashRAIDReportingState disable -ModifyPresent

# Create maintenance policy set to user-ack, apply on next reboot
Get-UcsOrg -Level root | Add-UcsMaintenancePolicy -Name "user_ack" -UptimeDisr user-ack -SoftShutdownTimer never -TriggerConfig on-next-boot -ModifyPresent

# Set default maintenance policy to user-ack
Get-UcsOrg -Level root | Get-UcsMaintenancePolicy -Name "default" | Set-UcsMaintenancePolicy -UptimeDisr user-ack -Force

# Create a network control policy that enables CDP and disables LLDP
$mo = Get-UcsOrg -Level root | Add-UcsNetworkControlPolicy -Name "cdp_on_lldp_off" -Cdp enabled -LldpReceive disabled -LldpTransmit disabled -UplinkFailAction link-down -MacRegisterMode only-native-vlan -Descr "CDP enabled, LLDP disabled" -ModifyPresent
$mo | Add-UcsPortSecurityConfig -Forge allow -ModifyPresent 

# Create management vNIC template redundancy pair
$mo = Get-UcsOrg -Level root | Add-UcsVnicTemplate -Name "esxi_mgmt_a" -IdentPoolName "esxi_mac_a_dc$site_id" -SwitchId A -RedundancyPairType primary -PeerRedundancyTemplName "esxi_mgmt_b" -CdnSource vnic-name -Mtu 1500 -NwCtrlPolicyName "cdp_on_lldp_off" -TemplType updating-template -ModifyPresent
$mo | Add-UcsVnicInterface -Name $mgmt_vlan"_mgmt_dc"$site_id -DefaultNet no -ModifyPresent
$mo = Get-UcsOrg -Level root | Add-UcsVnicTemplate -Name "esxi_mgmt_b" -IdentPoolName "esxi_mac_b_dc$site_id" -SwitchId B -RedundancyPairType secondary -PeerRedundancyTemplName "esxi_mgmt_a" -CdnSource vnic-name -ModifyPresent

# Create vMotion vNIC template redundancy pair
$mo = Get-UcsOrg -Level root | Add-UcsVnicTemplate -Name "esxi_vmotion_a" -IdentPoolName "esxi_mac_a_dc$site_id" -SwitchId A -RedundancyPairType primary -PeerRedundancyTemplName "esxi_vmotion_b" -CdnSource vnic-name -Mtu 9000 -NwCtrlPolicyName "cdp_on_lldp_off" -TemplType updating-template -ModifyPresent
$mo | Add-UcsVnicInterface -Name $vmotion_vlan"_vmotion_dc"$site_id -DefaultNet no -ModifyPresent
$mo = Get-UcsOrg -Level root | Add-UcsVnicTemplate -Name "esxi_vmotion_b" -IdentPoolName "esxi_mac_b_dc$site_id" -SwitchId B -RedundancyPairType secondary -PeerRedundancyTemplName "esxi_vmotion_a" -CdnSource vnic-name -ModifyPresent

# Create NFS vNIC template redundancy pair
$mo = Get-UcsOrg -Level root | Add-UcsVnicTemplate -Name "esxi_nfs_a" -IdentPoolName "esxi_mac_a_dc$site_id" -SwitchId A -RedundancyPairType primary -PeerRedundancyTemplName "esxi_nfs_b" -CdnSource vnic-name -Mtu 9000 -NwCtrlPolicyName "cdp_on_lldp_off" -TemplType updating-template -ModifyPresent
$mo | Add-UcsVnicInterface -Name $nfs_vlan"_nfs_dc"$site_id -DefaultNet no -ModifyPresent
$mo = Get-UcsOrg -Level root | Add-UcsVnicTemplate -Name "esxi_nfs_b" -IdentPoolName "esxi_mac_b_dc$site_id" -SwitchId B -RedundancyPairType secondary -PeerRedundancyTemplName "esxi_nfs_a" -CdnSource vnic-name -ModifyPresent

# Create iSCSI A vNIC template
$mo = Get-UcsOrg -Level root | Add-UcsVnicTemplate -Name "esxi_iscsi_a" -IdentPoolName "esxi_mac_a_dc$site_id" -SwitchId A -Mtu 9000 -NwCtrlPolicyName "cdp_on_lldp_off" -TemplType updating-template -ModifyPresent
$mo | Add-UcsVnicInterface -Name $iscsi_a_vlan"_iscsi_a_dc"$site_id -DefaultNet yes -ModifyPresent

# Create iSCSI B vNIC template
$mo = Get-UcsOrg -Level root | Add-UcsVnicTemplate -Name "esxi_iscsi_b" -IdentPoolName "esxi_mac_b_dc$site_id" -SwitchId A -Mtu 9000 -NwCtrlPolicyName "cdp_on_lldp_off" -TemplType updating-template -ModifyPresent
$mo | Add-UcsVnicInterface -Name $iscsi_b_vlan"_iscsi_b_dc"$site_id -DefaultNet yes -ModifyPresent

# Create VM vNIC template redundancy pair
$mo = Get-UcsOrg -Level root  | Add-UcsVnicTemplate -Name "esxi_vm_a" -IdentPoolName "esxi_mac_a_dc$site_id" -SwitchId A -RedundancyPairType primary -PeerRedundancyTemplName "esxi_vm_b" -CdnSource vnic-name -Mtu 1500 -NwCtrlPolicyName "cdp_on_lldp_off" -TemplType updating-template -ModifyPresent
for ($i=$dynamic_vlan_start;$i -le $dynamic_vlan_end; $i++) {
    $mo | Add-UcsVnicInterface -Name "vm_dynamic_$i" -DefaultNet no -ModifyPresent
}
$mo = Get-UcsOrg -Level root | Add-UcsVnicTemplate -Name "esxi_vm_b" -IdentPoolName "esxi_mac_b_dc$site_id" -SwitchId B -RedundancyPairType secondary -PeerRedundancyTemplName "esxi_vm_a" -CdnSource vnic-name -ModifyPresent

# Create LAN connectivity policy
$mo = Get-UcsOrg -Level root | Add-UcsVnicLanConnPolicy -Name "esxi_lan" -ModifyPresent
$mo | Add-UcsVnic -Name "vmnic0" -NwTemplName "esxi_mgmt_a" -AdaptorProfileName "VMWare" -Order "1" -ModifyPresent
$mo | Add-UcsVnic -Name "vmnic1" -NwTemplName "esxi_mgmt_b" -AdaptorProfileName "VMWare" -Order "2" -ModifyPresent
$mo | Add-UcsVnic -Name "vmnic2" -NwTemplName "esxi_vmotion_a" -AdaptorProfileName "VMWare" -Order "3" -ModifyPresent
$mo | Add-UcsVnic -Name "vmnic3" -NwTemplName "esxi_vmotion_b" -AdaptorProfileName "VMWare" -Order "4" -ModifyPresent
$mo | Add-UcsVnic -Name "vmnic4" -NwTemplName "esxi_nfs_a" -AdaptorProfileName "VMWare" -Order "5" -ModifyPresent
$mo | Add-UcsVnic -Name "vmnic5" -NwTemplName "esxi_nfs_b" -AdaptorProfileName "VMWare" -Order "6" -ModifyPresent
$mo | Add-UcsVnic -Name "vmnic6" -NwTemplName "esxi_iscsi_a" -AdaptorProfileName "VMWare" -Order "7" -ModifyPresent
$mo | Add-UcsVnic -Name "vmnic7" -NwTemplName "esxi_iscsi_b" -AdaptorProfileName "VMWare" -Order "8" -ModifyPresent
$mo_1 = $mo | Add-UcsVnicIScsiLCP -Name "iscsi_a" -VnicName "vmnic6" -ModifyPresent
$mo_1 | Add-UcsVnicVlan -VlanName $iscsi_a_vlan"_iscsi_a_dc"$site_id -ModifyPresent
$mo_2 = $mo | Add-UcsVnicIScsiLCP -Name "iscsi_b" -VnicName "vmnic7" -ModifyPresent
$mo_2 | Add-UcsVnicVlan -VlanName $iscsi_b_vlan"_iscsi_b_dc"$site_id -ModifyPresent
$mo | Add-UcsVnic -Name "vmnic8" -NwTemplName "esxi_vm_a" -AdaptorProfileName "VMWare" -Order "9" -ModifyPresent
$mo | Add-UcsVnic -Name "vmnic9" -NwTemplName "esxi_vm_b" -AdaptorProfileName "VMWare" -Order "10" -ModifyPresent

# Create server pool qualification for 384GB memory servers
$mo = Get-UcsOrg -Level root | Add-UcsServerPoolQualification -Name "384gb_ram" -ModifyPresent
$mo | Add-UcsMemoryQualification -MinCap "393216" -MaxCap "393216" -ModifyPresent

# Create server pool qualification for 512GB memory servers
$mo = Get-UcsOrg -Level root | Add-UcsServerPoolQualification -Name "512gb_ram" -ModifyPresent
$mo | Add-UcsMemoryQualification -MinCap "524288" -MaxCap "524288" -ModifyPresent

# Create server pool qualification for 1TB memory servers
$mo = Get-UcsOrg -Level root | Add-UcsServerPoolQualification -Name "1tb_ram" -ModifyPresent
$mo | Add-UcsMemoryQualification -MinCap "1048576" -MaxCap "1048576" -ModifyPresent

# Create server pools
Get-UcsOrg -Level root | Add-UcsServerPool -Name "basic" -ModifyPresent
Get-UcsOrg -Level root | Add-UcsServerPool -Name "general_purpose" -ModifyPresent
Get-UcsOrg -Level root | Add-UcsServerPool -Name "performance" -ModifyPresent

# Create server pool policies
Get-UcsOrg -Level root | Add-UcsServerPoolPolicy -Name "basic" -PoolDn "org-root/compute-pool-basic" -Qualifier "384gb_ram" -ModifyPresent
Get-UcsOrg -Level root | Add-UcsServerPoolPolicy -Name "general_purpose" -PoolDn "org-root/compute-pool-general_purpose" -Qualifier "512gb_ram" -ModifyPresent
Get-UcsOrg -Level root | Add-UcsServerPoolPolicy -Name "performance" -PoolDn "org-root/compute-pool-performance" -Qualifier "1tb_ram" -ModifyPresent

# Create service profile templates for each environment
foreach ($env in $environments){
    $template_name = $env+"_esxi_dc"+$site_id
    $kvm_ip_pool = $env+"_kvm_ip_dc"+$site_id
    $mo = Get-UcsOrg -Name $env | Add-UcsServiceProfile `
        -Name $template_name `
        -IdentPoolName "default" `
        -LocalDiskPolicyName "accept_any" `
        -BootPolicyName "esxi_iscsi_boot" `
        -BiosProfileName "esxi_bios" `
        -MaintPolicyName "user_ack" `
        -ExtIPState pooled `
        -ExtIPPoolName $kvm_ip_pool `
        -Type updating-template `
        -ModifyPresent
    # Add server pool to service profile template
    Switch($env){
    prd {$server_pool = "performance"}
    dev {$server_pool = "basic"}
    default {$server_pool = "general_purpose"}
    }
    $mo | Add-UcsServerPoolAssignment -Name $server_pool -ModifyPresent
    # Add LAN connectivity policy to service profile template
    #
    # This uses the generic Set-UcsManagedObject method, because no specific cmdlet seems to exist
    $mo | Add-UcsManagedObject -ClassId vnicConnDef -PropertyMap @{lanConnPolicyName = "esxi_lan"} -ModifyPresent

    # Add iSCSI boot parameters   
    foreach ($fabric in $fabrics) {
        $target_ip = $ip_prefix+"."+$iscsi_blocks[$fabric]+"."+$target_host
        $iqn_pool = $env+"_iqn_"+$fabric.ToLower()+"_dc"+$site_id
        $iscsi_ip_pool = $env+"_iscsi_ip_"+$fabric.ToLower()+"_dc"+$site_id
        $iscsi_vnic = "iscsi_"+$fabric.ToLower()
        $mo_1 = $mo | Add-UcsVnicIScsiBootParams -ModifyPresent | Add-UcsVnicIScsiBootVnic -Name $iscsi_vnic -IqnIdentPoolName $iqn_pool -ModifyPresent
        $mo_2 = $mo_1 | Add-UcsVnicIPv4If -ModifyPresent | Add-UcsManagedObject -ClassId vnicIPv4PooledIscsiAddr -PropertyMap @{} -ModifyPresent
        $mo_2 | Set-UcsVnicIPv4PooledIscsiAddr -IdentPoolName $iscsi_ip_pool -Force
        # For some reason the next section needs to be wrapped in a transaction. When I execute these cmdlets separately the API returns an error.
        Start-UcsTransaction
        $mo_1 | Add-UcsVnicIPv4If -ModifyPresent
        $mo_3 = $mo_1 | Add-UcsVnicIScsiStaticTargetIf -Priority 1 -IpAddress $target_ip -Name $target_iqn -Port 3260 -ModifyPresent
        $mo_3 | Add-UcsVnicLun -Id 0 -ModifyPresent
        Complete-UcsTransaction
    }
}

# Disconnect from UCS Manager
Disconnect-Ucs -Ucs $handle
