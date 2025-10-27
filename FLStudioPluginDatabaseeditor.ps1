#requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'

# ---------- CONFIG ----------
$installedRoot = "$env:USERPROFILE\Documents\Image-Line\FL Studio\Presets\Plugin database\Installed"
$verifiedMap   = Join-Path $installedRoot 'VerifiedIDs.nfo'

# ---------- FUNCTIONS ----------
function Read-VerifiedMap {
    if (-not (Test-Path $verifiedMap)) {
        [System.Windows.Forms.MessageBox]::Show("Cannot find VerifiedIDs.nfo at:`n$verifiedMap", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return @()
    }
    
    $plugins = @()
    foreach ($line in Get-Content $verifiedMap) {
        if ($line -match '^(?<fmt>[^:]+):(?<bits>\d+):(?<regid>[^=]+)=(?<relpath>.+)$') {
            $plugins += [PSCustomObject]@{
                Format     = $matches['fmt']
                BitDepth   = [int]$matches['bits']
                RegistryID = $matches['regid']
                RelPath    = $matches['relpath'].Trim()
                NfoFolder  = Split-Path $matches['relpath'] -Parent
                NfoName    = Split-Path $matches['relpath'] -Leaf
            }
        }
    }
    return $plugins
}

function Read-NfoFile($relPath) {
    $full = Join-Path $installedRoot $relPath
    if (-not (Test-Path $full)) { return $null }

    $h = @{}
    foreach ($line in Get-Content $full) {
        if ($line -match '^\s*([^=]+)\s*=\s*(.*)\s*$') {
            $h[$matches[1].Trim()] = $matches[2].Trim()
        }
    }

    # Use the first file entry (index 0) for primary data
    $name = $h['ps_name']
    $vendor = $h['ps_file_vendorname_0']
    $path = $h['ps_file_filename_0']
    $scanFlags = [int]($h['ps_file_scanflags_0'] -as [int])
    $bitSize = [int]($h['ps_file_bitsize_0'] -as [int])
    
    # Determine type from path
    $type = if ($relPath -match '\\Effects\\') { 'Effect' } 
             elseif ($relPath -match '\\Generators\\') { 'Generator' } 
             else { 'Unknown' }
    
    # Determine format from path
    $format = if ($relPath -match '\\(VST3|VST|CLAP)\\') { $matches[1] } 
              elseif ($relPath -match '\\Fruity\\') { 'Fruity' }
              else { '?' }

    return [PSCustomObject]@{
        RelPath   = $relPath
        FullPath  = $full
        Name      = $name
        Vendor    = $vendor
        Path      = $path
        ScanFlags = $scanFlags
        BitSize   = $bitSize
        Type      = $type
        Format    = $format
        RegistryID= ''
        NfoFolder = ''
        NfoName   = ''
        RegVendor = ''
        RegFile   = ''
        _Hash     = $h
    }
}

function Write-NfoFile($obj) {
    $h = $obj._Hash
    if (-not $h) { return }

    # Update the hash with edited values
    $h['ps_name'] = $obj.Name
    $h['ps_file_filename_0'] = $obj.Path
    $h['ps_file_vendorname_0'] = $obj.Vendor
    $h['ps_file_scanflags_0'] = $obj.ScanFlags.ToString()
    $h['ps_file_bitsize_0'] = $obj.BitSize.ToString()

    # Write back to file
    $lines = foreach ($k in ($h.Keys | Sort-Object)) {
        "$k=$($h[$k])"
    }

    [System.IO.File]::WriteAllLines($obj.FullPath, $lines, [System.Text.Encoding]::UTF8)
}

function Add-RegistryData($plugins) {
    foreach ($p in $plugins) {
        if ($p.RegistryID) {
            $regPath = "HKCU:\SOFTWARE\Image-Line\Shared\Plugins\$($p.RegistryID)"
            if (Test-Path $regPath) {
                try {
                    $reg = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
                    if ($reg) {
                        $p.RegVendor = if ($reg.Vendor) { $reg.Vendor -join '' } else { '' }
                        $p.RegFile = if ($reg.Filename) { $reg.Filename -join '' } else { '' }
                    }
                } catch {
                    $p.RegVendor = ''
                    $p.RegFile = ''
                }
            }
        }
    }
    return $plugins
}

# ---------- GUI LAUNCH ----------
# Ensure STA mode for Windows Forms
[System.Threading.Thread]::CurrentThread.SetApartmentState([System.Threading.ApartmentState]::STA)

$form = New-Object System.Windows.Forms.Form
$form.Text = "FL Studio 2025 Verified Plug-in Editor"
$form.Size = New-Object System.Drawing.Size(1400,700)
$form.StartPosition = "CenterScreen"

# Menu Setup
$menu = New-Object System.Windows.Forms.MenuStrip
$fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem("File")
$saveItem = New-Object System.Windows.Forms.ToolStripMenuItem("Save")
$saveItem.ShortcutKeys = "Control, S"
$fileMenu.DropDownItems.Add($saveItem) | Out-Null
$menu.Items.Add($fileMenu) | Out-Null
$form.MainMenuStrip = $menu
$form.Controls.Add($menu)

# Grid Setup
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = "Fill"
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.SelectionMode = "FullRowSelect"
$grid.MultiSelect = $false
$grid.AutoGenerateColumns = $false
$grid.AutoSizeColumnsMode = "None"
$form.Controls.Add($grid)

# Columns Definition
$columns = @(
    @{Name='Type';       Header='Type';       Width=80;  ReadOnly=$true},
    @{Name='Format';     Header='Format';     Width=70;  ReadOnly=$true},
    @{Name='BitSize';    Header='Bits';       Width=50;  ReadOnly=$false},
    @{Name='Name';       Header='Name';       Width=200; ReadOnly=$false},
    @{Name='Vendor';     Header='Vendor';     Width=140; ReadOnly=$false},
    @{Name='Path';       Header='DLL Path';   Width=380; ReadOnly=$false},
    @{Name='ScanFlags';  Header='ScanFlags';  Width=80;  ReadOnly=$false},
    @{Name='RegistryID'; Header='Registry ID';Width=240; ReadOnly=$true},
    @{Name='NfoFolder';  Header='NFO Folder'; Width=120; ReadOnly=$true},
    @{Name='NfoName';    Header='NFO File';   Width=150; ReadOnly=$true},
    @{Name='RegVendor';  Header='Vendor (Reg)';Width=140; ReadOnly=$true},
    @{Name='RegFile';    Header='Registered File Path';Width=380; ReadOnly=$true}
)

foreach ($c in $columns) {
    $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $col.DataPropertyName = $c.Name
    $col.HeaderText = $c.Header
    $col.Width = $c.Width
    $col.ReadOnly = $c.ReadOnly
    $grid.Columns.Add($col) | Out-Null
}

# Load data and populate grid
Write-Host "Loading VerifiedIDs.nfo..."
$map = Read-VerifiedMap

if ($map.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show("No plugins found in VerifiedIDs.nfo", "Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    # Exit script if no data is found to prevent an empty GUI launch attempt
    exit 1 
}

Write-Host "Found $($map.Count) entries in VerifiedIDs.nfo"
Write-Host "Loading individual NFO files..."

$data = @()
$loadedCount = 0
foreach ($m in $map) {
    $nfo = Read-NfoFile $m.RelPath
    if ($nfo) {
        # Merge VerifiedIDs data with NFO data
        $nfo.RegistryID = $m.RegistryID
        $nfo.NfoFolder = $m.NfoFolder
        $nfo.NfoName = $m.NfoName
        $data += $nfo
        $loadedCount++
    } else {
        Write-Host "Warning: Could not load $($m.RelPath)"
    }
}

Write-Host "Successfully loaded $loadedCount NFO files"
Write-Host "Adding registry data..."
$data = Add-RegistryData $data
Write-Host "Done loading. Displaying in grid..."

$grid.DataSource = New-Object System.Collections.ArrayList(,$data)

# Save handler (Uses $grid.DataSource for cleaner data access)
$saveItem.Add_Click({
    try {
        # Commit any ongoing cell edits to the underlying data source
        $grid.EndEdit()
        
        $savedCount = 0
        foreach ($obj in $grid.DataSource) { 
            if ($obj) { 
                Write-NfoFile $obj 
                $savedCount++
            }
        }
        [System.Windows.Forms.MessageBox]::Show("Successfully saved $savedCount .NFO files!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error saving files: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

# Show form - THE CRITICAL FIX
Write-Host "Running application message loop..."
# This starts the message loop, making the window visible and responsive
[void][System.Windows.Forms.Application]::Run($form)

# Clean up resources once the user closes the form
$form.Dispose()

Write-Host "Script finished."
