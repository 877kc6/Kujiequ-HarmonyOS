# ASCII-only Windows PowerShell 5.1 updater, run using Update.cmd.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$source = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([char]92)
$picker = New-Object System.Windows.Forms.FolderBrowserDialog
$picker.Description = 'Select the EXISTING Kujiequ project folder (with entry and build-profile.json5)'
$picker.ShowNewFolderButton = $false
if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { Write-Host 'Cancelled.'; exit 0 }
$target = [System.IO.Path]::GetFullPath($picker.SelectedPath).TrimEnd([char]92)
if (!(Test-Path -LiteralPath (Join-Path $target 'build-profile.json5')) -or !(Test-Path -LiteralPath (Join-Path $target 'entry\src\main\ets'))) {
  throw 'Wrong destination: select your existing project root with entry and build-profile.json5.'
}
if ($source.Equals($target,[System.StringComparison]::OrdinalIgnoreCase) -or
    $target.StartsWith($source + '\',[System.StringComparison]::OrdinalIgnoreCase) -or
    $source.StartsWith($target + '\',[System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'New source and existing project must be separate directories.'
}
$skipDirs = @('.git','.idea','.hvigor','oh_modules','node_modules','build','.cxx','.gradle')
$skipFiles = @('local.properties','Apply_Update.ps1','Update.cmd')
$files = @(Get-ChildItem -LiteralPath $source -Recurse -File | Where-Object {
  $relative = $_.FullName.Substring($source.Length + 1)
  $pieces = @($relative -split '[\\/]')
  $blocked = $false
  foreach ($piece in $pieces) { if ($skipDirs -contains $piece) { $blocked = $true; break } }
  (-not $blocked) -and (-not ($skipFiles -contains $_.Name))
})
if ($files.Count -lt 100) { throw 'Incomplete source package: extract the entire ZIP and retry.' }
$backup = Join-Path (Split-Path -Parent $target) ((Split-Path -Leaf $target) + '_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
if (Test-Path -LiteralPath $backup) { throw 'Backup path already exists. Retry in a second.' }
New-Item -ItemType Directory -Path $backup -ErrorAction Stop | Out-Null
$existing = New-Object 'System.Collections.Generic.List[string]'
$created = New-Object 'System.Collections.Generic.List[string]'
try {
  foreach ($file in $files) {
    $relative = $file.FullName.Substring($source.Length + 1)
    $dest = Join-Path $target $relative
    if (Test-Path -LiteralPath $dest) {
      $saved = Join-Path $backup $relative
      New-Item -ItemType Directory -Path (Split-Path -Parent $saved) -Force | Out-Null
      Copy-Item -LiteralPath $dest -Destination $saved -Force -ErrorAction Stop
      $existing.Add($relative)
    } else { $created.Add($relative) }
  }
  foreach ($file in $files) {
    $relative = $file.FullName.Substring($source.Length + 1)
    $dest = Join-Path $target $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $dest -Force -ErrorAction Stop
  }
  Write-Host ('SUCCESS: updated ' + $files.Count + ' files.') -ForegroundColor Green
  Write-Host ('Backup: ' + $backup)
} catch {
  $reason = $_.Exception.Message
  Write-Host ('Update failed: ' + $reason) -ForegroundColor Red
  foreach ($relative in $existing) {
    $saved = Join-Path $backup $relative
    $dest = Join-Path $target $relative
    if (Test-Path -LiteralPath $saved) { Copy-Item -LiteralPath $saved -Destination $dest -Force -ErrorAction Continue }
  }
  foreach ($relative in $created) {
    $dest = Join-Path $target $relative
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force -ErrorAction Continue }
  }
  throw ('Update failed; rollback attempted. Reason: ' + $reason)
}
