#requires -Modules posh-ssh 
$vmhosts = @("node1","node2","node3","node4")
$creds = Get-Credential
$brandstringcmd = "echo 'cpuid.brandstring = `"AMD EPYC Ryzen 9 7945HX`"' >> /etc/vmware/config"
$apichvcmd = "echo 'monitor_control.disable_apichv =`"TRUE`"' >> /etc/vmware/config"

foreach ($i in $vmhosts){
    write-host -fore green `n`t "Connecting to $i"   
    connect-viserver $i -credential $creds

    write-host -fore green `n`t "Setting AMD Ryzen Entropy on $i"   
    $esxcli = get-esxcli -v2
    $entropyArgs = $esxcli.system.settings.kernel.set.CreateArgs()
    $entropyArgs.setting = "entropySources"
    $entropyArgs.value = 2
    $esxcli.system.settings.kernel.set.Invoke($entropyArgs)

    write-host -fore green `n`t "Enabling & starting SSH"
    Get-VmHostService | Where-Object {$_.key -match "TSM-SSH"} | Set-VMHostService -Policy "on" -confirm:$false | Start-VMHostService -confirm:$false

    write-host -fore green `n`t "SSHing into the host to set cpuid.brandstring"
    $ssh = New-SSHSession -computername $i -credential $creds -Force -KeepAliveInterval 5 -Verbose -WarningAction SilentlyContinue
    $brandstringresult = Invoke-SSHCommand -SessionId $ssh.SessionId -Command $brandstringcmd -TimeOut 30
    if ($brandstringresult.ExitStatus -eq 0) {
            Write-Host "Brand string command executed successfully on $i." -ForegroundColor Green
        } else {
            Write-Host "Brand string command execution failed on $i. Exit status: $($brandstringresult.ExitStatus)" -ForegroundColor Red
        }
    
    $apichvresult = Invoke-SSHCommand -SessionId $ssh.SessionId -Command $apichvcmd -TimeOut 30
    if ($apichvresult.ExitStatus -eq 0) {
        Write-Host "API CHV command executed successfully on $i." -ForegroundColor Green
    } else {
        Write-Host "API CHV command execution failed on $i. Exit status: $($apichvresult.ExitStatus)" -ForegroundColor Red
    }

    Remove-SSHSession -SessionId $ssh.SessionId

    write-host -fore green `n`t "Rebooting $i"
    Restart-VMHost $i -Force -Confirm:$false -RunAsync

    write-host -fore green `n`t "Done, moving on"
    disconnect-viserver $i -confirm:$false
}
