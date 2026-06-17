# Requires -Modules VMware.PowerCLI

$vCenterFQDN = Read-Host -Prompt "Enter vCenter FQDN or IP"
$credentials = Get-Credential -Message "Enter vCenter Credentials"
$hostCredentials = Get-Credential -Message "Enter ESXi Host Root Credentials"

try {
    Write-Host "Connecting to vCenter: $vCenterFQDN..." -fore Cyan
    Connect-VIServer -Server $vCenterFQDN -Credential $credentials -ErrorAction Stop

    Write-Host "Fetching ESXi hosts from vCenter..." -fore Cyan
    $vmHosts = @(Get-VMHost | Select-Object -ExpandProperty Name)
    
    Write-Host "Disconnecting from vCenter ($vCenterFQDN)..." -fore Cyan
    Disconnect-VIServer -Server $vCenterFQDN -Confirm:$false -Force

    Write-Host "Connecting directly to ESXi hosts..." -fore Cyan
    Connect-VIServer -Server $vmHosts -Credential $hostCredentials -ErrorAction Stop

    Write-Host "Fetching all powered on VMs..." -fore Cyan
    $poweredOnVMs = @(Get-VM | ?{$_.PowerState -eq 'PoweredOn' })

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
            
            $nonNsxahvVKSVms = @($pendingVMs | ?{$_.Name -notmatch 'ahv|cci|harbor|vks' })
            if ($nonNsxahvVKSVms.Count -eq 0) {
                Write-Host "Only AHV,NSX, or VKS VMs remain. Forcefully powering them off..." -fore Cyan
                $pendingVMs | Stop-VM -Confirm:$false -ErrorAction SilentlyContinue
            }

            Start-Sleep -Seconds 10
            $pendingVMs = @(Get-VM -Id $poweredOnVMs.Id | ?{$_.PowerState -eq 'PoweredOn' })
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