# Ensure runtime is running in STA mode for UI Dialog stability in PowerShell 5.1
if ($Host.Runspace.ApartmentState -ne 'STA') {
    Write-Warning "Relaunching script in forced -STA mode..."
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $MyInvocation.MyCommand.Path
    return
}

# Explicitly load legacy Windows desktop Assemblies
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")

# Create the main Form window
$form = New-Object System.Windows.Forms.Form
$form.Text = "PowerShell 5.1 Image Resizer"
$form.Size = New-Object System.Drawing.Size(400, 250)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# 1. File Selection Label & Button
$lblFile = New-Object System.Windows.Forms.Label
$lblFile.Location = New-Object System.Drawing.Point(20, 20)
$lblFile.Size = New-Object System.Drawing.Size(240, 23)
$lblFile.Text = "No file selected..."
$lblFile.BorderStyle = "Fixed3D"
$form.Controls.Add($lblFile)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Location = New-Object System.Drawing.Point(270, 18)
$btnBrowse.Size = New-Object System.Drawing.Size(90, 25)
$btnBrowse.Text = "Browse Image"
$form.Controls.Add($btnBrowse)

# 2. Width Input
$lblWidth = New-Object System.Windows.Forms.Label
$lblWidth.Location = New-Object System.Drawing.Point(20, 70)
$lblWidth.Size = New-Object System.Drawing.Size(100, 23)
$lblWidth.Text = "Target Width (px):"
$form.Controls.Add($lblWidth)

$txtWidth = New-Object System.Windows.Forms.TextBox
$txtWidth.Location = New-Object System.Drawing.Point(130, 68)
$txtWidth.Size = New-Object System.Drawing.Size(80, 23)
$txtWidth.Text = "800"
$form.Controls.Add($txtWidth)

# 3. Height Input
$lblHeight = New-Object System.Windows.Forms.Label
$lblHeight.Location = New-Object System.Drawing.Point(20, 110)
$lblHeight.Size = New-Object System.Drawing.Size(100, 23)
$lblHeight.Text = "Target Height (px):"
$form.Controls.Add($lblHeight)

$txtHeight = New-Object System.Windows.Forms.TextBox
$txtHeight.Location = New-Object System.Drawing.Point(130, 108)
$txtHeight.Size = New-Object System.Drawing.Size(80, 23)
$txtHeight.Text = "600"
$form.Controls.Add($txtHeight)

# 4. Action Button
$btnResize = New-Object System.Windows.Forms.Button
$btnResize.Location = New-Object System.Drawing.Point(20, 160)
$btnResize.Size = New-Object System.Drawing.Size(340, 35)
$btnResize.Text = "Resize and Save Image"
$btnResize.Enabled = $false
$form.Controls.Add($btnResize)

# --- Global Tracking Variable ---
$script:selectedImagePath = ""

# --- Event Handlers ---

# Open File Dialog Box
$btnBrowse.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "Image Files (*.jpg;*.jpeg;*.png;*.bmp)|*.jpg;*.jpeg;*.png;*.bmp"
    
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:selectedImagePath = $openFileDialog.FileName
        # Audited Fix: Use robust .NET method to pull file names with extensions
        $lblFile.Text = [System.IO.Path]::GetFileName($script:selectedImagePath)
        
        # Read dimensions and immediately close stream to avoid persistent lockouts
        try {
            $originalImg = [System.Drawing.Image]::FromFile($script:selectedImagePath)
            $txtWidth.Text = $originalImg.Width.ToString()
            $txtHeight.Text = $originalImg.Height.ToString()
            $originalImg.Dispose() # Immediately clear system file handle lock
            $btnResize.Enabled = $true
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to read image attributes.", "Error", "OK", "Error")
        }
    }
})

# Core Resizing Logic Execution
$btnResize.Add_Click({
    if (-not (Test-Path $script:selectedImagePath)) {
        [System.Windows.Forms.MessageBox]::Show("Selected file path is missing or invalid.", "Error", "OK", "Error")
        return
    }

    # Validate Integer Bounds
    [int]$newWidth = 0
    [int]$newHeight = 0
    if (-not [int]::TryParse($txtWidth.Text, [ref]$newWidth) -or $newWidth -le 0 -or
        -not [int]::TryParse($txtHeight.Text, [ref]$newHeight) -or $newHeight -le 0) {
        [System.Windows.Forms.MessageBox]::Show("Please enter valid positive numbers for width and height.", "Validation Error", "OK", "Warning")
        return
    }

    try {
        $sourceImg = [System.Drawing.Image]::FromFile($script:selectedImagePath)
        $destBmp = New-Object System.Drawing.Bitmap($newWidth, $newHeight)
        $graphic = [System.Drawing.Graphics]::FromImage($destBmp)
        
        # Configure High-Quality Interpolation Overlays
        $graphic.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphic.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphic.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphic.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        
        # Render the Scaled Graphic Canvas
        $graphic.DrawImage($sourceImg, 0, 0, $newWidth, $newHeight)
        
        # Audited Fix: All path adjustments transitioned completely to System.IO to stay inside the .NET 4.5+ runtime framework
        $directory = [System.IO.Path]::GetDirectoryName($script:selectedImagePath)
        $filename = [System.IO.Path]::GetFileNameWithoutExtension($script:selectedImagePath)
        $extension = ([System.IO.Path]::GetExtension($script:selectedImagePath)).ToLower()
        $newFileName = "${filename}_resized${extension}"
        $outputPath = [System.IO.Path]::Combine($directory, $newFileName)
        
        # Maps extensions directly to explicit Imaging.ImageFormat objects to avoid raw format save errors
        switch ($extension) {
            ".png"  { $imgFormat = [System.Drawing.Imaging.ImageFormat]::Png }
            ".bmp"  { $imgFormat = [System.Drawing.Imaging.ImageFormat]::Bmp }
            default { $imgFormat = [System.Drawing.Imaging.ImageFormat]::Jpeg }
        }
        
        # Commit Image Data Stream cleanly to Disk
        $destBmp.Save($outputPath, $imgFormat)
        
        # Clean Up Memory Allocation Handles explicitly
        $graphic.Dispose()
        $destBmp.Dispose()
        $sourceImg.Dispose()
        
        [System.Windows.Forms.MessageBox]::Show("Image successfully resized!`nSaved to: $outputPath", "Success", "OK", "Information")
    }
    catch {
        # Ensure cleanup runs even if saving fails
        if ($null -ne $graphic) { $graphic.Dispose() }
        if ($null -ne $destBmp) { $destBmp.Dispose() }
        if ($null -ne $sourceImg) { $sourceImg.Dispose() }
        [System.Windows.Forms.MessageBox]::Show("An error occurred during resizing:`n$_", "Execution Error", "OK", "Error")
    }
})

# Display Window Layout Canvas
$form.ShowDialog() | Out-Null