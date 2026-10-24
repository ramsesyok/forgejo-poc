#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$HostAddress)
$ErrorActionPreference = 'Stop'
$ip = $null
if (-not [System.Net.IPAddress]::TryParse($HostAddress, [ref]$ip) -or
    $ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'HostAddress must be an IPv4 address'
}
$sshDir = Join-Path $env:USERPROFILE '.ssh'
$config = Join-Path $sshDir 'config'
$key = Join-Path $sshDir 'forgejo-lab_ed25519'
if (-not (Test-Path -LiteralPath $key -PathType Leaf)) { throw "SSH key not found: $key" }
New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
$old = if (Test-Path -LiteralPath $config) { [System.IO.File]::ReadAllText($config) } else { '' }
$begin = '# BEGIN forgejo-lab managed by forgejo-poc'
$end = '# END forgejo-lab managed by forgejo-poc'
$block = @"
$begin
Host forgejo-lab
    HostName $HostAddress
    User devops
    IdentityFile $($key.Replace('\', '/'))
    IdentitiesOnly yes
    StrictHostKeyChecking yes
$end
"@
if ($old.Contains($begin)) {
    $pattern = [regex]::Escape($begin) + '[\s\S]*?' + [regex]::Escape($end)
    if (-not [regex]::IsMatch($old, $pattern)) { throw 'Incomplete managed SSH config block' }
    $new = ([regex]::new($pattern)).Replace($old, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block }, 1)
} else {
    if ($old -match '(?im)^\s*Host\s+forgejo-lab\s*$') { throw 'Unmanaged forgejo-lab Host entry already exists' }
    $separator = if ($old.Length -eq 0) { '' } elseif ($old.EndsWith("`n")) { "`n" } else { "`r`n`r`n" }
    $new = $old + $separator + $block + "`r`n"
}
if (Test-Path -LiteralPath $config) {
    $backup = "$config.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $config -Destination $backup
}
[System.IO.File]::WriteAllText($config, $new, [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated $config for forgejo-lab -> $HostAddress"
