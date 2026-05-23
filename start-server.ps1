# Serves Creature on all interfaces. Use the Wi-Fi IP on phones (not Ethernet 10.x unless phone is on that LAN).
$port = 3456
$root = $PSScriptRoot

Write-Host ""
Write-Host "Creature dev server" -ForegroundColor Green
Write-Host "  This PC:     http://localhost:$port/"
foreach ($addr in Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.IPAddress -notmatch '^127\.' -and $_.IPAddress -notmatch '^169\.'
  }) {
  Write-Host "  $($addr.InterfaceAlias): http://$($addr.IPAddress):$port/" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "On your phone: use the Wi-Fi line above (often 192.168.x.x)." -ForegroundColor Yellow
Write-Host "gamepc2 hostname usually does NOT work on phones." -ForegroundColor Yellow
Write-Host ""

Set-Location $root
python -m http.server $port --bind 0.0.0.0
