# Requires -Modules VMware.PowerCLI

#$vCenter = Read-Host -Prompt "Enter vCenter Server Name or IP"
#$creds = Get-Credential -Message "Enter credentials for vCenter Server $vCenter"

#Write-Host "Connecting to vCenter: $vCenter..." -ForegroundColor Cyan
#Connect-VIServer -Server $vCenter -Credential $creds -ErrorAction Stop

$vmHosts = Get-VMHost | Where-Object { $_.ConnectionState -eq 'Connected' }

foreach ($vmHost in $vmHosts) {
    Write-Host "Setting MemoryTiering to FALSE on host: $($vmHost.Name)..." -ForegroundColor Cyan
    
    try {
        $esxcli = Get-EsxCli -VMHost $vmHost -V2 -ErrorAction Stop
        
        $kernelArgs = $esxcli.system.settings.kernel.set.CreateArgs()
        $kernelArgs.setting = "MemoryTiering"
        $kernelArgs.value = "FALSE"
        
        $esxcli.system.settings.kernel.set.Invoke($kernelArgs)
        Write-Host "  Successfully updated setting on $($vmHost.Name)." -ForegroundColor Green
    } catch {
        Write-Error "  Failed to set kernel setting on host $($vmHost.Name): $_"
    }
}

Write-Host "`nDisconnecting from vCenter..." -ForegroundColor Cyan
Disconnect-VIServer -Server $vCenter -Confirm:$false -Force -ErrorAction SilentlyContinue
