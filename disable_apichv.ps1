#requires -Modules posh-ssh 
#requires -Modules VMware.PowerCLI
$vmhosts = @("node1","node2","node3","node4")
$creds = Get-Credential

$cmd = "echo 'monitor_control.disable_apichv =`"TRUE`"' >> /etc/vmware/config"

foreach ($i in $vmhosts){
    write-host -fore green `n`t "Connecting to $i"   
    connect-viserver $i -credential $creds
    if ((Get-VmHostService | Where-Object {$_.key -match "TSM-SSH"}).Running -ne "Running"){
        $startSSH = 1
        write-host -fore green `n`t "Enabling SSH"
        Get-VmHostService | Where-Object {$_.key -match "TSM-SSH"} | Set-VMHostService -Policy "on" -confirm:$false | Start-VMHostService -confirm:$false
    }
    
    write-host -fore green `n`t "SSHing into $i to set monitor_control.disable_apichv"
    try {
        $ssh = New-SSHSession -computername $i -credential $creds -Force -KeepAliveInterval 5 -Verbose -WarningAction SilentlyContinue -ErrorAction Stop
        Write-Host "Connected to $i. Executing command..." -ForegroundColor Cyan
        $result = Invoke-SSHCommand -SessionId $ssh.SessionId -Command $cmd
        if ($result.ExitStatus -eq 0) {
            Write-Host "Command executed successfully on $i." -ForegroundColor Green
        } else {
            Write-Host "Command execution failed on $i. Exit status: $($result.ExitStatus)" -ForegroundColor Red
        }
    } catch {
        Write-Host "Failed to connect to $i. ($_.Exception.Message)" -ForegroundColor Red
    }
    Remove-SSHSession -SessionId $ssh.SessionId
    if($startSSH -eq 1){
        write-host -fore green `n`t "Disabling SSH"
        Get-VmHostService | Where-Object {$_.key -match "TSM-SSH"} | Stop-VMHostService -Confirm:$false | Set-VMHostService -Policy "off" -confirm:$false
    }
    Disconnect-VIServer $i -Confirm:$false -Force -ErrorAction SilentlyContinue
    write-host -fore green `n`t "Done, moving on"
}