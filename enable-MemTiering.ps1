# Requires -Modules VMware.PowerCLI

$vCenter = Read-Host -Prompt "Enter vCenter Server Name or IP"
$creds = Get-Credential -Message "Enter credentials for vCenter Server $vCenter"
$memTieringPct = Read-Host -Prompt "Enter desired Mem.TierNvmePct value (e.g. 50 for 50%)"

Write-Host "Connecting to vCenter: $vCenter..." -ForegroundColor Cyan
Connect-VIServer -Server $vCenter -Credential $creds -ErrorAction Stop

$vmHosts = Get-VMHost | Where-Object { $_.ConnectionState -eq 'Connected' }

foreach ($vmHost in $vmHosts) {
    Write-Host "Setting MemoryTiering to TRUE on host: $($vmHost.Name)..." -ForegroundColor Cyan
    
    try {
        $esxcli = Get-EsxCli -VMHost $vmHost -V2 -ErrorAction Stop
        
        $kernelArgs = $esxcli.system.settings.kernel.set.CreateArgs()
        $kernelArgs.setting = "MemoryTiering"
        $kernelArgs.value = "TRUE"
        $esxcli.system.settings.kernel.set.Invoke($kernelArgs)
        Write-Host "  Successfully enabled MemoryTiering on host$($vmHost.Name)." -ForegroundColor Green

        Write-Host "  Setting /Mem/TierNvmePct to $memTieringPct% on host: $($vmHost.Name)..." -ForegroundColor Cyan
        $memTieringArgs = $esxcli.system.settings.advanced.set.CreateArgs()
        $memTieringArgs.option = "/Mem/TierNvmePct"
        $memTieringArgs.intvalue = $memTieringPct
        $esxcli.system.settings.advanced.set.Invoke($memTieringArgs)
        Write-Host "  Successfully set Mem.TierNvmePct to $memTieringPct% on host$($vmHost.Name)." -ForegroundColor Green
        
    } catch {
        Write-Error "  Failed to set kernel setting on host $($vmHost.Name): $_"
    }
}

Write-Host "`nDisconnecting from vCenter..." -ForegroundColor Cyan
Disconnect-VIServer -Server $vCenter -Confirm:$false -Force -ErrorAction SilentlyContinue
