# Make Windows run Spider-Man 2 on the high-performance GPU (laptops with an integrated + a discrete GPU).
# Same switch as Settings > System > Display > Graphics > Webhead.exe > High performance.
# Run it yourself, e.g.:   powershell -ExecutionPolicy Bypass -File prefer_dgpu.ps1 "D:\Games\Spider-Man 2\System\Webhead.exe"
#                          add -Undo to go back to "let Windows decide".
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [switch]$Undo
)

$exe = (Resolve-Path $Exe).Path
$key = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }

if ($Undo) {
    Remove-ItemProperty -Path $key -Name $exe -ErrorAction SilentlyContinue
    Write-Host "Removed the GPU preference for $exe"
} else {
    # GpuPreference: 0 = let Windows decide, 1 = power saving, 2 = high performance
    Set-ItemProperty -Path $key -Name $exe -Value 'GpuPreference=2;'
    Write-Host "Spider-Man 2 ($exe) now prefers the high-performance GPU. Restart the game."
}
