$vmhosts = @("cougar.thephuck.lab","mach-e.thephuck.lab","f250.thephuck.lab","mustang.thephuck.lab")
$creds = get-credential

try {
    # Connect to all hosts
    foreach ($i in $vmhosts){
        Write-Host -ForegroundColor Green "`n`t Connecting to $i"   
        Connect-VIServer $i -Credential $creds -ErrorAction Stop | Out-Null
    }
    # Power on vCenter
    Write-Host -ForegroundColor Green "`n`t Powering on vCenter"
    start-vm vc01 -ErrorAction Stop | Out-Null
    write-host -fore green "`n`t Waiting 5 minutes for vCenter to boot up..."
    sleep 300
    
    # Power on NSX
    Write-Host -ForegroundColor Green "`n`t Powering on NSX"
    start-vm nsx01a, edge* -ErrorAction Stop | Out-Null
    write-host -fore green "`n`t Waiting 5 minutes for NSX to boot up..."
    sleep 300

    # Power on VCF stuffs
    write-host -fore green "`n`t Powering on VCF stuffs"
    get-vm sddc01, vcf-svcs*, vna*, vcfops*, vcf-lice*, vcf-auto* | start-vm -ErrorAction Stop | Out-Null
    write-host -fore green "`n`t Waiting 5 minutes for VCF stuffs to boot up..."
    sleep 300

}
catch{
    Write-Host -ForegroundColor Red "Error: $_"
}

Write-Host -ForegroundColor Green "`nDone!"
Disconnect-VIServer * -Confirm:$false -Force -ErrorAction SilentlyContinue