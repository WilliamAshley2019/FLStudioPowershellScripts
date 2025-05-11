# PowerShell script to set UserPostMessageLimit in Windows Registry

# Define the registry path and value name
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows"
$valueName = "UserPostMessageLimit"
$valueData = 100000

# Check if the key exists
if (-not (Test-Path $regPath)) {
    Write-Error "Registry path does not exist: $regPath"
    exit 1
}

# Create or update the registry value
try {
    New-ItemProperty -Path $regPath -Name $valueName -Value $valueData -PropertyType DWORD -Force
    Write-Output "Successfully set $valueName to $valueData at $regPath"
} catch {
    Write-Error "Failed to write to registry. Try running PowerShell as Administrator."
}

# Optional: Prompt for restart
$choice = Read-Host "Do you want to restart now to apply changes? (y/n)"
if ($choice -eq 'y') {
    Restart-Computer -Force
}
