# Created by Pierre Vandervoort and Bijan Purkian

# --- Helper: map BitLocker method to bit length ---
function Map-Method([string]$m) {
    switch ($m) {
        'XtsAes256' { '256-bit' }
        'Aes256'    { '256-bit' }
        'XtsAes128' { '128-bit' }
        'Aes128'    { '128-bit' }
        default     { 'Unknown' }
    }
}

$results = @()
$deviceName = $env:COMPUTERNAME

try {
    Import-Module BitLocker -ErrorAction Stop -WarningAction SilentlyContinue

    # --- Build target drive list (always include OS drive) ---
    $targets = @()
    $targets += $env:SystemDrive
    $volumes = Get-Volume -ErrorAction SilentlyContinue |
               Where-Object { $_.DriveType -eq 'Fixed' -and $_.FileSystem -eq 'NTFS' -and $_.DriveLetter }
    foreach ($v in $volumes) {
        $targets += ("{0}:" -f $v.DriveLetter)
    }
    $targets = $targets | Sort-Object -Unique

    foreach ($d in $targets) {
        try {
            $vol = Get-BitLockerVolume -MountPoint $d -ErrorAction Stop

            $method = Map-Method -m ([string]$vol.EncryptionMethod)
            $protection = if ($vol.ProtectionStatus -eq 'On') { 'On' } else { 'Off' }

            $results += [pscustomobject]@{
                Drive            = $d
                Status           = [string]$vol.VolumeStatus              # e.g. FullyEncrypted
                Protection       = $protection
                Method           = $method
                EncryptionMethod = [string]$vol.EncryptionMethod          # raw enum
                KeyProtectorIds  = ($vol.KeyProtector | ForEach-Object { $_.KeyProtectorId }) -join ','
                LastWriteUtc     = (Get-Date).ToUniversalTime().ToString('o')
                IsOSDrive        = ($d.TrimEnd(':').ToUpper() -eq $env:SystemDrive.TrimEnd(':').ToUpper())
            }
        }
        catch {
            $results += [pscustomobject]@{
                Drive            = $d
                Status           = 'Exception'
                Protection       = 'Unknown'
                Method           = 'Unknown'
                EncryptionMethod = $null
                KeyProtectorIds  = $null
                LastWriteUtc     = (Get-Date).ToUniversalTime().ToString('o')
                IsOSDrive        = ($d.TrimEnd(':').ToUpper() -eq $env:SystemDrive.TrimEnd(':').ToUpper())
            }
        }
    }
}
catch {
    # Module failure or unexpected issue
    $results = @([pscustomobject]@{
        Drive='Unknown'; Status='Exception'; Protection='Unknown'; Method='Unknown'
        EncryptionMethod=$null; KeyProtectorIds=$null
        LastWriteUtc=(Get-Date).ToUniversalTime().ToString('o'); IsOSDrive=$false
    })
}

# --- Output compact JSON for Intune ---
$payload = @{
    Device = $deviceName
    Items  = $results
} | ConvertTo-Json -Depth 4 -Compress

Write-Output $payload

# --- Always exit 0 (report-only) ---
exit 0
