# FLP WAV Finder GUI with Enhancements
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object Windows.Forms.Form -Property @{
    Text = "FLP WAV Finder"
    Size = '720,600'
    StartPosition = 'CenterScreen'
}

# Global cancel token
$global:cancelSearch = $false

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

$btnCancel = New-Object Windows.Forms.Button -Property @{ Text = "Cancel"; Location = '120,75'; Width = 100 }
$btnCancel.Add_Click({ $global:cancelSearch = $true })
$form.Controls.Add($btnCancel)

$listBox = New-Object Windows.Forms.ListBox -Property @{
    Location = '10,110'; Size = '680,350'; Font = 'Courier New, 9'; DrawMode = 'OwnerDrawFixed'
}
$form.Controls.Add($listBox)

$progress = New-Object Windows.Forms.ProgressBar -Property @{ Location = '10,470'; Size = '680,20'; Minimum = 0; Maximum = 100; Value = 0 }
$form.Controls.Add($progress)

$lblStatus = New-Object Windows.Forms.Label -Property @{ Text = "Status: Idle"; Location = '10,500'; Size = '680,30' }
$form.Controls.Add($lblStatus)

$contextMenu = New-Object Windows.Forms.ContextMenu
$contextMenu.MenuItems.Add("Copy Path", { Set-Clipboard -Value $listBox.SelectedItem })
$contextMenu.MenuItems.Add("Open File Location", {
    $path = ($listBox.SelectedItem -split '=>')[1].Trim()
    if (Test-Path $path) {
        Start-Process "explorer.exe" "/select,`"$path`""
    }
})
$listBox.ContextMenu = $contextMenu

function Show-Status($msg, $progressVal = $null) {
    $lblStatus.Text = "Status: $msg"
    if ($progressVal -ne $null) { $progress.Value = $progressVal }
    [Windows.Forms.Application]::DoEvents()
}

function Extract-WavsFromFLP($flp) {
    $bytes = [System.IO.File]::ReadAllBytes($flp)
    $ascii = -join ($bytes | ForEach-Object { if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { ' ' } })
    $regex = '(?:[A-Z]:|%[^%]+%)\\(?:[^\\:*?"<>|\r\n]+\\)*[^\\:*?"<>|\r\n]+\.wav|\S+\.wav'
    $matches = [regex]::Matches($ascii, $regex)
    $paths = $matches | ForEach-Object { $_.Value } | Sort-Object -Unique
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

$btnStart.Add_Click({
    $global:cancelSearch = $false
    $flp = $txtFLP.Text
    $outDir = $txtOut.Text
    if (-not (Test-Path $flp)) { [Windows.Forms.MessageBox]::Show("Invalid FLP path."); return }
    if (-not (Test-Path $outDir)) { New-Item -Path $outDir -ItemType Directory | Out-Null }

    $logFile = Join-Path $outDir "SearchLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $indexFile = Join-Path $outDir "MasterSampleIndex.log"

    Show-Status "Reading FLP..."
    $wavFiles = Extract-WavsFromFLP $flp
    $listBox.Items.Clear()
    $wavFiles | ForEach-Object { $listBox.Items.Add("Searching: $_") }

    $foundPaths = @{}
    Copy-Item $flp -Destination (Join-Path $outDir (Split-Path $flp -Leaf)) -Force
    $priority = @("$env:USERPROFILE\Desktop", "$env:USERPROFILE\Music", "$env:USERPROFILE", "C:\Samples", "C:\")

    $total = $wavFiles.Count
    for ($i = 0; $i -lt $total; $i++) {
        if ($global:cancelSearch) { Show-Status "Cancelled."; break }

        $wav = [System.IO.Path]::GetFileName($wavFiles[$i])
        $found = $false

        foreach ($dir in $priority) {
            Show-Status "Searching in $dir for $wav", [int](($i / $total) * 100)
            try {
                $match = Get-ChildItem -Path $dir -Recurse -Filter $wav -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($match) {
                    $found = $true
                    $path = $match.FullName
                    Copy-Item $path -Destination (Join-Path $outDir $wav) -Force
                    $foundPaths[$wav] = $path
                    $listBox.Items[$i] = "Found: $wav => $path"
                    Add-Content -Path $indexFile "$wav=$path"
                    Add-Content -Path $logFile "Found: $wav => $path"
                    break
                }
            } catch {}
        }

        if (-not $found) {
            Show-Status "Scanning full drive for $wav", [int](($i / $total) * 100)
            try {
                $match = Get-ChildItem -Path C:\ -Recurse -Filter $wav -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($match) {
                    $path = $match.FullName
                    Copy-Item $path -Destination (Join-Path $outDir $wav) -Force
                    $foundPaths[$wav] = $path
                    $listBox.Items[$i] = "Found: $wav => $path"
                    Add-Content -Path $indexFile "$wav=$path"
                    Add-Content -Path $logFile "Found: $wav => $path"
                } else {
                    $listBox.Items[$i] = "Missing: $wav"
                    Add-Content -Path $logFile "Missing: $wav"
                }
            } catch {
                $listBox.Items[$i] = "Missing: $wav"
                Add-Content -Path $logFile "Missing: $wav"
            }
        }
    }
    Show-Status "Search Complete.", 100
})

[Windows.Forms.Application]::Run($form)
