Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object Windows.Forms.Form -Property @{
    Text = "FLP WAV Finder"
    Size = '700,550'
    StartPosition = 'CenterScreen'
}

# GUI Controls
$labelFLP = New-Object Windows.Forms.Label -Property @{ Text = "FLP File:"; Location = '10,10'; AutoSize = $true }
$form.Controls.Add($labelFLP)

$txtFLP = New-Object Windows.Forms.TextBox -Property @{ Location = '80,10'; Width = 500 }
$form.Controls.Add($txtFLP)

$btnBrowseFLP = New-Object Windows.Forms.Button -Property @{ Text = "Browse"; Location = '590,10' }
$btnBrowseFLP.Add_Click({
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Filter = "FL Studio Project (*.flp)|*.flp"
    if ($dlg.ShowDialog() -eq "OK") { $txtFLP.Text = $dlg.FileName }
})
$form.Controls.Add($btnBrowseFLP)

$labelOut = New-Object Windows.Forms.Label -Property @{ Text = "Output Folder:"; Location = '10,40'; AutoSize = $true }
$form.Controls.Add($labelOut)

$txtOut = New-Object Windows.Forms.TextBox -Property @{ Location = '100,40'; Width = 480 }
$form.Controls.Add($txtOut)

$btnBrowseOut = New-Object Windows.Forms.Button -Property @{ Text = "Browse"; Location = '590,40' }
$btnBrowseOut.Add_Click({
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq "OK") { $txtOut.Text = $dlg.SelectedPath }
})
$form.Controls.Add($btnBrowseOut)

$btnStart = New-Object Windows.Forms.Button -Property @{ Text = "Start Search"; Location = '10,75'; Width = 100 }
$form.Controls.Add($btnStart)

$listBox = New-Object Windows.Forms.ListBox -Property @{
    Location = '10,110'; Size = '660,350'; Font = 'Courier New, 9'; DrawMode = 'OwnerDrawFixed'
}
$form.Controls.Add($listBox)

$lblStatus = New-Object Windows.Forms.Label -Property @{ Text = "Status: Idle"; Location = '10,470'; Size = '660,30' }
$form.Controls.Add($lblStatus)

# Status update function
function Show-Status($msg) {
    $lblStatus.Text = "Status: $msg"
    [Windows.Forms.Application]::DoEvents()
}

# Extract WAVs from FLP
function Extract-WavsFromFLP($flp) {
    $bytes = [System.IO.File]::ReadAllBytes($flp)

    # Convert bytes to printable ASCII string
    $ascii = -join ($bytes | ForEach-Object {
        if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { ' ' }
    })

    # Match absolute and relative .wav file paths
    $regex = '(?:[A-Z]:|%[^%]+%)\\(?:[^\\:*?"<>|\r\n]+\\)*[^\\:*?"<>|\r\n]+\.wav|\S+\.wav'
    $matches = [regex]::Matches($ascii, $regex)
    $paths = $matches | ForEach-Object { $_.Value } | Sort-Object -Unique

    # Expand known FL Studio variables
    $expanded = @()
    foreach ($p in $paths) {
        $p2 = $p
        if ($p2 -like "%FLStudioFactoryData%*") {
            $userPath = Join-Path $env:USERPROFILE "Documents\Image-Line\Downloads"
            $p2 = $p2 -replace '%FLStudioFactoryData%', $userPath
        }
        $expanded += $p2
    }

    return $expanded
}

# Draw colored items with proper type casting for position
$listBox.add_DrawItem({
    param($s, $e)
    $e.DrawBackground()
    $item = $listBox.Items[$e.Index]
    $color = if ($item -like "Found:*") { 'Green' } elseif ($item -like "Missing:*") { 'Red' } else { 'Black' }
    $brush = New-Object Drawing.SolidBrush ([Drawing.Color]::$color)
    $point = New-Object Drawing.PointF $e.Bounds.X, $e.Bounds.Y
    $e.Graphics.DrawString($item, $e.Font, $brush, $point)
    $e.DrawFocusRectangle()
})

# Start button logic
$btnStart.Add_Click({
    $flp = $txtFLP.Text
    $outDir = $txtOut.Text

    if (-not (Test-Path $flp)) {
        [Windows.Forms.MessageBox]::Show("Invalid FLP path."); return
    }
    if (-not (Test-Path $outDir)) {
        New-Item -Path $outDir -ItemType Directory | Out-Null
    }

    Show-Status "Reading FLP..."
    $wavFiles = Extract-WavsFromFLP $flp
    $listBox.Items.Clear()
    $wavFiles | ForEach-Object { $listBox.Items.Add("Searching: $_") }

    $foundPaths = @{}
    Copy-Item $flp -Destination (Join-Path $outDir (Split-Path $flp -Leaf)) -Force

    $priority = @("$env:USERPROFILE\Desktop", "$env:USERPROFILE\Music", "$env:USERPROFILE", "C:\Samples", "C:\")

    for ($i = 0; $i -lt $wavFiles.Count; $i++) {
        $wav = [System.IO.Path]::GetFileName($wavFiles[$i])
        $found = $false

        foreach ($dir in $priority) {
            Show-Status "Searching in $dir for $wav"
            try {
                $match = Get-ChildItem -Path $dir -Recurse -Filter $wav -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($match) {
                    $found = $true
                    $path = $match.FullName
                    Copy-Item $path -Destination (Join-Path $outDir $wav) -Force
                    $foundPaths[$wav] = $path
                    $listBox.Items[$i] = "Found: $wav => $path"
                    break
                }
            } catch {}
        }

        if (-not $found) {
            Show-Status "Scanning full drive for $wav"
            try {
                $match = Get-ChildItem -Path C:\ -Recurse -Filter $wav -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($match) {
                    $path = $match.FullName
                    Copy-Item $path -Destination (Join-Path $outDir $wav) -Force
                    $foundPaths[$wav] = $path
                    $listBox.Items[$i] = "Found: $wav => $path"
                } else {
                    $listBox.Items[$i] = "Missing: $wav"
                }
            } catch {
                $listBox.Items[$i] = "Missing: $wav"
            }
        }
    }

    Show-Status "Search Complete."
})

[Windows.Forms.Application]::Run($form)
