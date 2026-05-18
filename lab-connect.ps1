$vmhosts = @("cougar.thephuck.lab","mach-e.thephuck.lab","f250.thephuck.lab","mustang.thephuck.lab")
$creds = get-credential

foreach ($i in $vmhosts){
    write-host -fore green `n`t "Connecting to $i"   
    connect-viserver $i -credential $creds
}