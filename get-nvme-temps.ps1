# Requires -Modules VMware.PowerCLI

param (
    [switch]$csv
)

$vCenter = Read-Host -Prompt "Enter vCenter Server Name or IP"
$creds = Get-Credential -Message "Enter credentials for vCenter Server $vCenter"

Write-Host "Connecting to vCenter: $vCenter..." -ForegroundColor Cyan
Connect-VIServer -Server $vCenter -Credential $creds -ErrorAction Stop

$endTime = (Get-Date).AddHours(6)
if ($csv) {
    $csvPath = "c:\scripts\nvme-temps-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    Write-Host "`nStarting 6-hour NVMe temperature sampling loop. Output: $csvPath" -ForegroundColor Cyan
} else {
    Write-Host "`nStarting 6-hour NVMe temperature sampling loop." -ForegroundColor Cyan
}

while ((Get-Date) -lt $endTime) {
    $loopStart = Get-Date
    Write-Host "`n--- Sampling at $loopStart ---" -ForegroundColor Cyan
    $results = @()

# Iterate over all clusters and their connected hosts
foreach ($cluster in Get-Cluster) {
    $vmHosts = $cluster | Get-VMHost | Where-Object { $_.ConnectionState -eq 'Connected' }
    
    foreach ($vmHost in $vmHosts) {
        Write-Host "Checking Host: $($vmHost.Name) in Cluster: $($cluster.Name)..." -ForegroundColor Cyan
        
        try {
            $esxcli = Get-EsxCli -VMHost $vmHost -V2 -ErrorAction Stop
            $nvmeDevices = $esxcli.nvme.device.list.Invoke()
            
            if ($null -eq $nvmeDevices -or $nvmeDevices.Count -eq 0) {
                Write-Host "  No NVMe devices found on $($vmHost.Name)." -ForegroundColor Yellow
                continue
            }
            
            # Helper block to extract Kelvin values from esxcli output and convert to Celsius
            $convertToCelsius = {
                param($kString)
                
                # If esxcli returns an array, extract the first element.
                # (-match on an array acts as a filter and does NOT populate $matches)
                if ($kString -is [array] -and $kString.Count -gt 0) {
                    $kString = $kString[0]
                }
                
                $str = [string]$kString
                if (![string]::IsNullOrWhiteSpace($str) -and $str -match "(\d+)") {
                    $kelvin = [int]$matches[1]
                    $celsius = [math]::Round($kelvin - 273.15, 0)
                    return "$celsius C"
                }
                return "N/A"
            }

            # Gather mappings for NVMe roles
            $tieringCanonical = @()
            $vsanCacheCanonical = @()
            $vsanCapCanonical = @()
            $allPaths = @()
            
            try {
                $storageSystem = Get-View $vmHost.ExtensionData.ConfigManager.StorageSystem
                $tieringCanonical = @($storageSystem.StorageDeviceInfo.ScsiLun | Where-Object { $_.UsedByMemoryTiering -eq $true } | Select-Object -ExpandProperty CanonicalName)
                
                $allPaths = $esxcli.storage.core.path.list.Invoke()
            } catch {
                Write-Warning "  Could not retrieve core storage mapping info for $($vmHost.Name): $_"
            }

            try {
                $vsanStorage = $esxcli.vsan.storage.list.Invoke()
                if ($vsanStorage) {
                    $vsanCacheCanonical = @($vsanStorage | Where-Object { [string]$_.IsCapacityTier -eq 'false' } | Select-Object -ExpandProperty Device)
                    $vsanCapCanonical = @($vsanStorage | Where-Object { [string]$_.IsCapacityTier -eq 'true' } | Select-Object -ExpandProperty Device)
                }
            } catch {
                # vSAN might not be enabled or throws an error, ignore silently
            }

            foreach ($device in $nvmeDevices) {
                try {
                    $smartArgs = $esxcli.nvme.device.log.smart.get.CreateArgs()
                    $smartArgs.adapter = $device.HBAName
                    
                    $smartLog = $esxcli.nvme.device.log.smart.get.Invoke($smartArgs)
                    
                    # Extract current temperature from the SMART log
                    $currentTemp = &$convertToCelsius $smartLog.CompositeTemperature
                    
                    # Extract Over Temperature Threshold from feature tt
                    $ttArgs = $esxcli.nvme.device.feature.tt.get.CreateArgs()
                    $ttArgs.adapter = $device.HBAName
                    $ttLog = $esxcli.nvme.device.feature.tt.get.Invoke($ttArgs)
                    $overTempThreshold = &$convertToCelsius $ttLog.OverTemperatureThreshold
                    
                    # Determine Usage Role
                    $role = "Datastore/Other"
                    $cNames = @($allPaths | Where-Object { $_.Adapter -eq $device.HBAName } | Select-Object -ExpandProperty Device -Unique)
                    
                    foreach ($cName in $cNames) {
                        if ($tieringCanonical -contains $cName) {
                            $role = "Memory Tiering"
                            break
                        } elseif ($vsanCacheCanonical -contains $cName) {
                            $role = "vSAN Cache"
                            break
                        } elseif ($vsanCapCanonical -contains $cName) {
                            $role = "vSAN Capacity"
                            break
                        }
                    }

                    $results += [PSCustomObject]@{
                        Timestamp           = $loopStart.ToString("yyyy-MM-dd HH:mm:ss")
                        Cluster             = $cluster.Name
                        Host                = $vmHost.Name
                        NVMeAdapter         = $device.HBAName
                        Role                = $role
                        CurrentTemp         = $currentTemp
                        OverTempThreshold   = $overTempThreshold
                    }
                } catch {
                    Write-Warning "Failed to process NVMe device $($device.HBAName) on host $($vmHost.Name): $_"
                }
            }
        } catch {
            Write-Error "Failed to process NVMe data on host $($vmHost.Name): $_"
        }
    }
}

    if ($results) {
        if ($csv) {
            $results | Export-Csv -Path $csvPath -NoTypeInformation -Append
        }
        Write-Host "`nNVMe Temperature Report:" -ForegroundColor Green
        $results | Format-Table -AutoSize
    }
    
    $elapsed = ((Get-Date) - $loopStart).TotalSeconds
    $sleepTime = 60 - $elapsed
    if ($sleepTime -gt 0) {
        Write-Host "Sleeping for $([math]::Round($sleepTime)) seconds... (Press Ctrl+C to cancel)" -ForegroundColor DarkGray
        Start-Sleep -Seconds $sleepTime
    }
}

Write-Host "`n6-hour sampling complete. Disconnecting from vCenter..." -ForegroundColor Cyan
Disconnect-VIServer -Server $vCenter -Confirm:$false -Force -ErrorAction SilentlyContinue

if ($csv) {
    Write-Host "`nNVMe Temperature Report saved to: $csvPath" -ForegroundColor Green
}
