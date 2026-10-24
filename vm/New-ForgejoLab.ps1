#Requires -Version 5.1
<#
Creates only a new forgejo-lab VM. Run in an elevated PowerShell session when
VMware tools or the destination folder are restricted by the host.
#>
[CmdletBinding()]
param(
    [string]$InstallIso = 'C:\Users\ramse\Downloads\OracleLinux-R8-U10-x86_64-dvd.iso',
    [string]$VmRoot = 'C:\Users\ramse\Documents\Virtual Machines',
    [switch]$Start
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$vmDir = Join-Path $VmRoot 'forgejo-lab'
$vmx = Join-Path $vmDir 'forgejo-lab.vmx'
$disk = Join-Path $vmDir 'forgejo-lab.vmdk'
$bootIso = Join-Path $vmDir 'forgejo-lab-kickstart-boot.iso'
$work = Join-Path $repo '.work\boot-iso'
$key = Join-Path $env:USERPROFILE '.ssh\forgejo-lab_ed25519'
$passwordFile = Join-Path $env:USERPROFILE '.ssh\forgejo-lab-console-password.txt'
$vmware = 'C:\Program Files\VMware\VMware Workstation'
$diskTool = Join-Path $vmware 'vmware-vdiskmanager.exe'
$mkisofs = Join-Path $vmware 'mkisofs.exe'
$vmrun = Join-Path $vmware 'vmrun.exe'
$openssl = 'C:\Program Files\Git\usr\bin\openssl.exe'

if (-not (Test-Path -LiteralPath $InstallIso -PathType Leaf)) { throw "ISO not found: $InstallIso" }
if (-not (Test-Path -LiteralPath $VmRoot -PathType Container)) { throw "VM root not found: $VmRoot" }
if (Test-Path -LiteralPath $vmDir) {
    if ((Get-ChildItem -LiteralPath $vmDir -Force | Measure-Object).Count -ne 0) {
        throw "VM directory already contains files; refusing to modify it: $vmDir"
    }
}
foreach ($path in @($diskTool, $mkisofs, $vmrun, $openssl)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required tool missing: $path" }
}
$sshDir = Join-Path $env:USERPROFILE '.ssh'
New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
if ((Test-Path -LiteralPath $key) -xor (Test-Path -LiteralPath "$key.pub")) {
    throw "Incomplete SSH key pair at $key; refusing to overwrite it"
}
if (-not (Test-Path -LiteralPath $key)) {
    & ssh-keygen.exe -q -t ed25519 -f $key -N '' -C 'devops@forgejo-lab'
    if ($LASTEXITCODE -ne 0) { throw 'ssh-keygen failed' }
}
$pub = (Get-Content -LiteralPath "$key.pub" -Raw).Trim()
if ($pub -notmatch '^ssh-ed25519 [A-Za-z0-9+/=]+( .*)?$') { throw 'Unexpected public key format' }
if (Test-Path -LiteralPath $passwordFile) {
    $password = (Get-Content -LiteralPath $passwordFile -Raw).Trim()
} else {
    $alphabet = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#%^*_-'
    $random = [byte[]]::new(32)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($random)
    $rng.Dispose()
    $password = -join ($random | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
    [System.IO.File]::WriteAllText($passwordFile, "$password`r`n", [System.Text.Encoding]::ASCII)
    & icacls.exe $passwordFile /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restrict password file ACL' }
}
$startInfo = [System.Diagnostics.ProcessStartInfo]::new($openssl, 'passwd -6 -stdin')
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$hashProcess = [System.Diagnostics.Process]::Start($startInfo)
$passwordBytes = [System.Text.Encoding]::UTF8.GetBytes($password + "`n")
$hashProcess.StandardInput.BaseStream.Write($passwordBytes, 0, $passwordBytes.Length)
$hashProcess.StandardInput.Close()
$hash = $hashProcess.StandardOutput.ReadToEnd().Trim()
$hashError = $hashProcess.StandardError.ReadToEnd()
$hashProcess.WaitForExit()
if ($hashProcess.ExitCode -ne 0 -or $hash -notmatch '^\$6\$') { throw "Password hashing failed: $hashError" }
$passwordBytes = $null
$password = $null

New-Item -ItemType Directory -Path $work -Force | Out-Null
New-Item -ItemType Directory -Path $vmDir -Force | Out-Null
$ks = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'forgejo-lab.ks.in') -Raw).Replace('@@PASSWORD_HASH@@', $hash).Replace('@@PUBLIC_KEY@@', $pub)
[System.IO.File]::WriteAllText((Join-Path $work 'ks.cfg'), $ks, [System.Text.UTF8Encoding]::new($false))
$hash = $null

& tar.exe -xf $InstallIso -C $work 'isolinux/isolinux.bin' 'isolinux/ldlinux.c32' 'images/pxeboot/vmlinuz' 'images/pxeboot/initrd.img'
if ($LASTEXITCODE -ne 0) { throw 'Could not extract boot files from Oracle Linux ISO' }
Copy-Item -LiteralPath (Join-Path $work 'images\pxeboot\vmlinuz') -Destination (Join-Path $work 'isolinux\vmlinuz')
Copy-Item -LiteralPath (Join-Path $work 'images\pxeboot\initrd.img') -Destination (Join-Path $work 'isolinux\initrd.img')
$cfg = @'
default linux
prompt 0
timeout 10
label linux
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=OL-8-10-0-BaseOS-x86_64 inst.repo=hd:LABEL=OL-8-10-0-BaseOS-x86_64 inst.ks=cdrom:/ks.cfg inst.text ip=dhcp
'@
[System.IO.File]::WriteAllText((Join-Path $work 'isolinux\isolinux.cfg'), $cfg.Replace("`r`n", "`n") + "`n", [System.Text.Encoding]::ASCII)
Push-Location $vmware
try {
    & $mkisofs -quiet -o $bootIso -V FORGEJOKS -J -R -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table $work
} finally {
    Pop-Location
}
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $bootIso)) { throw 'Boot ISO creation failed' }

& $diskTool -c -s 100GB -a lsilogic -t 0 $disk
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $disk)) { throw 'Virtual disk creation failed' }
$vmxText = @"
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "20"
displayName = "forgejo-lab"
guestOS = "rhel8-64"
numvcpus = "4"
cpuid.coresPerSocket = "2"
memsize = "8192"
firmware = "bios"
bios.bootOrder = "hdd,cdrom"
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "forgejo-lab.vmdk"
scsi0:0.deviceType = "scsi-hardDisk"
ide1:0.present = "TRUE"
ide1:0.deviceType = "cdrom-image"
ide1:0.fileName = "$bootIso"
ide1:0.startConnected = "TRUE"
ide1:1.present = "TRUE"
ide1:1.deviceType = "cdrom-image"
ide1:1.fileName = "$InstallIso"
ide1:1.startConnected = "TRUE"
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "e1000"
ethernet0.addressType = "generated"
usb.present = "FALSE"
sound.present = "FALSE"
floppy0.present = "FALSE"
"@
[System.IO.File]::WriteAllText($vmx, $vmxText.Replace("`r`n", "`n") + "`n", [System.Text.Encoding]::ASCII)
Write-Host "Created VM: $vmx"
Write-Host "SSH key: $key"
Write-Host "Console/sudo password file: $passwordFile"
if ($Start) {
    & $vmrun -T ws start $vmx nogui
    if ($LASTEXITCODE -ne 0) { throw 'VM start failed' }
}
