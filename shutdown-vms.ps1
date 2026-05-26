# Requires -Modules VMware.PowerCLI

$vCenterFQDN = Read-Host -Prompt "Enter vCenter FQDN or IP"
$credentials = Get-Credential -Message "Enter vCenter Credentials"
$hostCredentials = Get-Credential -Message "Enter ESXi Host Root Credentials"

try {
    Write-Host "Connecting to vCenter: $vCenterFQDN..." -ForegroundColor Cyan
    Connect-VIServer -Server $vCenterFQDN -Credential $credentials -ErrorAction Stop

    Write-Host "Fetching ESXi hosts from vCenter..." -ForegroundColor Cyan
    $vmHosts = @(Get-VMHost | Select-Object -ExpandProperty Name)
    
    Write-Host "Disconnecting from vCenter ($vCenterFQDN)..." -ForegroundColor Cyan
    Disconnect-VIServer -Server $vCenterFQDN -Confirm:$false -Force

    Write-Host "Connecting directly to ESXi hosts..." -ForegroundColor Cyan
    Connect-VIServer -Server $vmHosts -Credential $hostCredentials -ErrorAction Stop

    Write-Host "Fetching all powered on VMs..." -ForegroundColor Cyan
    $poweredOnVMs = @(Get-VM | Where-Object { $_.PowerState -eq 'PoweredOn' })

    if ($poweredOnVMs.Count -eq 0) {
        Write-Host "No powered on VMs found." -ForegroundColor Green
    }
    else {
        Write-Host "Currently Powered-On VMs:" -ForegroundColor Yellow
        $poweredOnVMs | Select-Object Name | Format-Table -HideTableHeaders

        Write-Host "Initiating graceful shutdown (Shutdown Guest OS)..." -ForegroundColor Cyan
        $poweredOnVMs | Shutdown-VMGuest -Confirm:$false -ErrorAction SilentlyContinue

        $pendingVMs = $poweredOnVMs
        while ($pendingVMs.Count -gt 0) {
            Write-Host "Monitoring... $($pendingVMs.Count) VM(s) are still powered on." -ForegroundColor Yellow
            
            $nonNsxVms = @($pendingVMs | Where-Object { $_.Name -notmatch 'NSX' })
            if ($nonNsxVms.Count -eq 0) {
                Write-Host "Only NSX VMs remain. Forcefully powering them off..." -ForegroundColor Cyan
                $pendingVMs | Stop-VM -Confirm:$false -ErrorAction SilentlyContinue
            }

            Start-Sleep -Seconds 10
            $pendingVMs = @(Get-VM -Id $poweredOnVMs.Id | Where-Object { $_.PowerState -eq 'PoweredOn' })
        }
        
        Write-Host "All VMs have been successfully powered off." -ForegroundColor Green
    }
}
catch {
    Write-Error "An error occurred: $_"
}
finally {
    Write-Host "Cleaning up connections..." -ForegroundColor Cyan
    Disconnect-VIServer -Server * -Confirm:$false -Force -ErrorAction SilentlyContinue
}