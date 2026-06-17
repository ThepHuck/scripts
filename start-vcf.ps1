$vmhosts = @("cougar.thephuck.lab","mach-e.thephuck.lab","f250.thephuck.lab","mustang.thephuck.lab")
$creds = get-credential

try {
    $hostsToReboot = @()

    # Connect to all hosts
    foreach ($i in $vmhosts){
        Write-Host -ForegroundColor Green "`n`t Connecting to $i"   
        Connect-VIServer $i -Credential $creds -ErrorAction Stop | Out-Null
    }

    # Check memory tiering status, enable and reboot if necessary
    foreach ($i in $vmhosts) {
        $vmHost = Get-VMHost -Server $i -ErrorAction Stop
        $tieringType = $vmHost.ExtensionData.Hardware.memoryTieringType

        if ($tieringType -ne "softwareTiering") {
            Write-Host -ForegroundColor Yellow "Memory tiering is disabled on $($vmHost.Name). Enabling..."
            $esxcli = Get-EsxCli -VMHost $vmHost -V2 -Server $i -ErrorAction Stop
            
            $kernelArgs = $esxcli.system.settings.kernel.set.CreateArgs()
            $kernelArgs.setting = "MemoryTiering"
            $kernelArgs.value = "TRUE"
            $esxcli.system.settings.kernel.set.Invoke($kernelArgs)
            
            Write-Host -ForegroundColor Green "  Successfully enabled MemoryTiering on host $($vmHost.Name)."
            
            Write-Host -ForegroundColor Cyan "  Rebooting host $($vmHost.Name)..."
            Restart-VMHost -VMHost $vmHost -Server $i -Force -Confirm:$false -RunAsync | Out-Null
            $hostsToReboot += $i
        } else {
            Write-Host -ForegroundColor Green "Memory tiering is already enabled on $($vmHost.Name)."
        }
    }

    # Monitor reboots and re-verify memory tiering
    if ($hostsToReboot.Count -gt 0) {
        foreach ($h in $hostsToReboot) {
            Disconnect-VIServer -Server $h -Confirm:$false -Force -ErrorAction SilentlyContinue
        }

        Write-Host -ForegroundColor Cyan "`nWaiting 30 seconds before monitoring reboots..."
        Start-Sleep -Seconds 30

        $pendingHosts = $hostsToReboot | Select-Object -Unique
        while ($pendingHosts.Count -gt 0) {
            $stillPending = @()
            foreach ($h in $pendingHosts) {
                if (Test-Connection -ComputerName $h -Count 1 -Quiet -ErrorAction SilentlyContinue) {
                    try {
                        Connect-VIServer $h -Credential $creds -ErrorAction Stop | Out-Null
                        $vmHost = Get-VMHost -Server $h -ErrorAction Stop
                        
                        if ($vmHost.ConnectionState -eq "Connected") {
                            Write-Host -ForegroundColor Green "Host $h is back online. Verifying configuration..."
                            $tieringType = $vmHost.ExtensionData.Hardware.memoryTieringType
                            if ($tieringType -ne "softwareTiering") {
                                Write-Host -ForegroundColor Red "Memory tiering is STILL disabled on $h! Please check manually."
                            } else {
                                Write-Host -ForegroundColor Green "Verified memory tiering is enabled on $h."
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
                Write-Host -ForegroundColor Yellow "Still waiting on: $($pendingHosts -join ', ')... checking again in 30 seconds."
                Start-Sleep -Seconds 30
            }
        }
    }

    # Power on non-AHV VMs
    Write-Host -ForegroundColor Cyan "`nPowering on non-ahv VMs..."
    foreach ($i in $vmhosts) {
        $vms = Get-VM -Server $i -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*ahv" }
        if ($vms) {
            foreach ($vm in $vms) {
                if ($vm.PowerState -ne "PoweredOn") {
                    Write-Host -ForegroundColor Green "Powering on $($vm.Name) on host $i"
                    Start-VM -VM $vm -Server $i -RunAsync | Out-Null
                } else {
                    Write-Host -ForegroundColor Yellow "$($vm.Name) on host $i is already powered on."
                }
            }
        } else {
            Write-Host -ForegroundColor Yellow "No non-ahv VMs found on host $i."
        }
    }
}
catch{
    Write-Host -ForegroundColor Red "Error: $_"
}

Write-Host -ForegroundColor Green "`nDone!"
Disconnect-VIServer * -Confirm:$false -Force -ErrorAction SilentlyContinue