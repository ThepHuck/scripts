# Requires -Modules VMware.PowerCLI
$vmhosts = @("cougar.thephuck.lab","mach-e.thephuck.lab","f250.thephuck.lab","mustang.thephuck.lab")
$hostCredentials = Get-Credential -Message "Enter ESXi Host Root Credentials"

$ignoreVMs = @("metrics-aggregator*","harbor*","auto-attach*","cci-ns-controller-manager*","configuration-service-controller-manager*")

try {
    Write-Host "Connecting directly to ESXi hosts..." -fore Cyan
    Connect-VIServer -Server $vmHosts -Credential $hostCredentials -ErrorAction Stop

    Write-Host "Fetching all powered on VMs..." -fore Cyan
    $ignorePattern = ($ignoreVMs -join '|') -replace '\*', '.*'
    $poweredOnVMs = @(Get-VM | Where-Object { $_.PowerState -eq 'PoweredOn' -and $_.Name -notmatch $ignorePattern })

    if ($poweredOnVMs.Count -eq 0) {
        Write-Host "No powered on VMs found." -fore Green
    }
    else {
        Write-Host "Currently Powered-On VMs:" -fore Yellow
        $poweredOnVMs | Select-Object Name | Format-Table -HideTableHeaders

        Write-Host "Initiating graceful shutdown (Shutdown Guest OS)..." -fore Cyan
        $poweredOnVMs | Shutdown-VMGuest -Confirm:$false -ErrorAction SilentlyContinue

        $pendingVMs = $poweredOnVMs
        while ($pendingVMs.Count -gt 0) {
            Write-Host "Monitoring... $($pendingVMs.Count) VM(s) are still powered on." -fore Yellow

            Start-Sleep -Seconds 10
            $pendingVMs = @(Get-VM -Id $poweredOnVMs.Id | Where-Object { $_.PowerState -eq 'PoweredOn' })
        }
        
        Write-Host "All VMs have been successfully powered off." -fore Green
    }
}
catch {
    Write-Error "An error occurred: $_"
}
finally {
    Write-Host "Cleaning up connections..." -fore Cyan
    Disconnect-VIServer -Server * -Confirm:$false -Force -ErrorAction SilentlyContinue
}