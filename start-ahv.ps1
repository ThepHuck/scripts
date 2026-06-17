$vmhosts = @("cougar.thephuck.lab","mach-e.thephuck.lab","f250.thephuck.lab","mustang.thephuck.lab")
$creds = get-credential

$hostsToReboot = @()

# Connect to all hosts
foreach ($i in $vmhosts){
    Write-Host -fore Green "`n`t Connecting to $i"   
    Connect-VIServer $i -Credential $creds -ErrorAction Stop | Out-Null
}

# Check memory tiering status, disable and reboot if necessary
foreach ($i in $vmhosts) {
    $vmHost = Get-VMHost -Server $i -ErrorAction Stop
    $tieringType = $vmHost.ExtensionData.Hardware.memoryTieringType

    if ($tieringType -eq "softwareTiering") {
        Write-Host -fore Yellow "Memory tiering is enabled on $($vmHost.Name). Disabling..."
        $esxcli = Get-EsxCli -VMHost $vmHost -V2 -Server $i -ErrorAction Stop
        
        $kernelArgs = $esxcli.system.settings.kernel.set.CreateArgs()
        $kernelArgs.setting = "MemoryTiering"
        $kernelArgs.value = "FALSE"
        $esxcli.system.settings.kernel.set.Invoke($kernelArgs)
        
        Write-Host -fore Green "  Successfully disabled MemoryTiering on host $($vmHost.Name)."
        
        Write-Host -fore Cyan "  Rebooting host $($vmHost.Name)..."
        Restart-VMHost -VMHost $vmHost -Server $i -Force -Confirm:$false -RunAsync | Out-Null
        $hostsToReboot += $i
    } else {
        Write-Host -fore Green "Memory tiering is already disabled on $($vmHost.Name)."
    }
}

# Monitor reboots and re-verify memory tiering
if ($hostsToReboot.Count -gt 0) {
    foreach ($h in $hostsToReboot) {
        Disconnect-VIServer -Server $h -Confirm:$false -Force -ErrorAction SilentlyContinue
    }

    Write-Host -fore Cyan "`nWaiting 30 seconds before monitoring reboots..."
    Start-Sleep -Seconds 30

    $pendingHosts = $hostsToReboot | select -Unique
    while ($pendingHosts.Count -gt 0) {
        $stillPending = @()
        foreach ($h in $pendingHosts) {
            if (Test-Connection -ComputerName $h -Count 1 -Quiet -ErrorAction SilentlyContinue) {
                try {
                    Connect-VIServer $h -Credential $creds -ErrorAction Stop | Out-Null
                    $vmHost = Get-VMHost -Server $h -ErrorAction Stop
                    
                    if ($vmHost.ConnectionState -eq "Connected") {
                        Write-Host -fore Green "Host $h is back online. Verifying configuration..."
                        $tieringType = $vmHost.ExtensionData.Hardware.memoryTieringType
                        if ($tieringType -eq "softwareTiering") {
                            Write-Host -fore Red "Memory tiering is STILL enabled on $h! Please check manually."
                        } else {
                            Write-Host -fore Green "Verified memory tiering is disabled on $h."
                        }
                    } else {
                        $stillPending += $h
                    }
                } catch {
                    $stillPending += $h
                }
            } else {
                $stillPending += $h
            }
        }
        $pendingHosts = $stillPending
        if ($pendingHosts.Count -gt 0) {
            Write-Host -fore Yellow "Still waiting on: $($pendingHosts -join ', ')... checking again in 30 seconds."
            Start-Sleep -Seconds 30
        }
    }
}

# Power on AHV VMs
Write-Host -fore Cyan "`nPowering on '-ahv' VMs..."
foreach ($i in $vmhosts) {
    $ahvVMs = Get-VM -Server $i -ErrorAction SilentlyContinue | ? {$_.name -match "ahv|vc01|nsx01a"}
    if ($ahvVMs) {
        foreach ($vm in $ahvVMs) {
            if ($vm.PowerState -ne "PoweredOn") {
                Write-Host -fore Green "Powering on $($vm.Name) on host $i"
                Start-VM -VM $vm -Server $i -RunAsync | Out-Null
            } else {
                Write-Host -fore Yellow "$($vm.Name) on host $i is already powered on."
            }
        }
    } else {
        Write-Host -fore Yellow "No ahv, vc01, or nsx01a VMs found on host $i."
    }
}

Write-Host -fore Green "`nDone!"
Disconnect-VIServer * -Confirm:$false -Force -ErrorAction SilentlyContinue
