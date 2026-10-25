Add-Type -AssemblyName System.Windows.Forms
$ErrorActionPreference = 'Stop'
$changed = @()
$original = @{}
$backupRoot = $null
try {
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  $dialog.Description = '选择旧工程的 Kujiequ 文件夹（包含 entry 和 build-profile.json5）'
  if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 0 }
  $targetRoot = $dialog.SelectedPath
  if (!(Test-Path (Join-Path $targetRoot 'build-profile.json5')) -or !(Test-Path (Join-Path $targetRoot 'entry/src/main/ets'))) { throw '请选择旧工程根目录。' }
  if ([IO.Path]::GetFullPath($targetRoot).TrimEnd('\') -eq [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')) { throw '请选择旧工程，不要选择新解压的文件夹。' }
  $files = @(
    'entry/src/main/ets/pages/CaptureProbe.ets',
    'entry/src/main/ets/services/CaptureProbeModel.ets',
    'entry/src/main/ets/services/CaptureProbeStore.ets',
    'entry/src/main/ets/vpnability/CaptureProbeAbility.ets',
    'entry/src/main/cpp/probe.h',
    'entry/src/main/cpp/probe.cpp',
    'entry/src/main/cpp/napi_init.cpp',
    'entry/src/main/cpp/CMakeLists.txt',
    'entry/src/main/cpp/types/libcapture_probe/index.d.ts',
    'entry/src/main/cpp/types/libcapture_probe/oh-package.json5',
    'tests/capture_probe.test.cjs',
    'tests/capture_probe_native_test.cpp',
    'docs/LOCAL_CAPTURE_TEST.md',
    'entry/src/main/ets/components/AppBackdrop.ets',
    'entry/src/main/ets/components/SafePage.ets',
    'entry/src/main/ets/components/Feed.ets',
    'entry/src/main/ets/components/GameData.ets',
    'entry/src/main/ets/components/HumanCaptcha.ets',
    'entry/src/main/ets/entryability/EntryAbility.ets',
    'entry/src/main/ets/models/Models.ets',
    'entry/src/main/ets/pages/Index.ets',
    'entry/src/main/ets/pages/History.ets',
    'entry/src/main/ets/pages/AccountList.ets',
    'entry/src/main/ets/pages/Compose.ets',
    'entry/src/main/ets/services/GameBoards.ets',
    'entry/src/main/resources/base/media/compose.svg',
    'entry/src/main/resources/base/profile/main_pages.json',
    'entry/src/main/ets/pages/Login.ets',
    'entry/src/main/ets/pages/Post.ets',
    'entry/src/main/ets/pages/Settings.ets',
    'entry/src/main/ets/pages/WebPage.ets',
    'entry/src/main/ets/services/KuroApi.ets',
    'entry/src/main/ets/services/AccountData.ets',
    'entry/src/main/ets/services/LocalStore.ets',
    'entry/src/main/ets/services/Protocol.ets',
    'entry/src/main/ets/services/Session.ets',
    'entry/src/main/ets/services/UiTheme.ets',
    'entry/src/main/ets/services/WebSession.ets',
    'entry/src/main/resources/rawfile/human_captcha.html',
    'entry/src/main/resources/dark/element/color.json',
    'README.md',
    'NEXT_VERSION.md',
    'docs/API.md',
    'docs/API26_DESIGN_REVIEW.md',
    'docs/VALIDATION.md',
    'tests/services.test.cjs',
    'tests/check_project.py'
  )
  foreach ($item in $files) { if (!(Test-Path -LiteralPath (Join-Path $PSScriptRoot $item))) { throw ('更新包缺少：' + $item) } }
  $appFile = Join-Path $targetRoot 'AppScope/app.json5'
  $appText = Get-Content -LiteralPath $appFile -Raw -Encoding UTF8
  if ($appText -notmatch '"versionCode"\s*:\s*\d+' -or $appText -notmatch '"versionName"\s*:\s*"[^"\r\n]+"') { throw '旧工程版本配置格式无法识别，未开始更新。' }
  $appText = [regex]::Replace($appText, '"versionCode"\s*:\s*\d+', '"versionCode": 1006001')
  $appText = [regex]::Replace($appText, '"versionName"\s*:\s*"[^"\r\n]+"', '"versionName": "1.6.1-probe"')
  # Merge only required additions; retain the user's signing, bundle and native options.
  $mergedFiles = @{}
  $modulePath = 'entry/src/main/module.json5'
  $module = Get-Content -LiteralPath (Join-Path $targetRoot $modulePath) -Raw -Encoding UTF8 | ConvertFrom-Json
  $exts = @($module.module.extensionAbilities | Where-Object { $_ -and $_.name -ne 'CaptureProbeAbility' })
  $exts += [pscustomobject]@{ name='CaptureProbeAbility'; srcEntry='./ets/vpnability/CaptureProbeAbility.ets'; type='vpn'; exported=$false }
  $module.module | Add-Member -NotePropertyName extensionAbilities -NotePropertyValue $exts -Force
  $mergedFiles[$modulePath] = $module | ConvertTo-Json -Depth 40
  $buildPath = 'entry/build-profile.json5'
  $build = Get-Content -LiteralPath (Join-Path $targetRoot $buildPath) -Raw -Encoding UTF8 | ConvertFrom-Json
  if (!$build.buildOption) { $build | Add-Member -NotePropertyName buildOption -NotePropertyValue ([pscustomobject]@{}) -Force }
  $native = $build.buildOption.externalNativeOptions
  if ($native -and $native.path -and $native.path -ne './src/main/cpp/CMakeLists.txt') { throw '旧工程已有其他 Native CMake 入口，需要手动合并；没有开始替换。' }
  if (!$native) { $native = [pscustomobject]@{ path='./src/main/cpp/CMakeLists.txt'; arguments=''; cppFlags='' } }
  $native | Add-Member -NotePropertyName path -NotePropertyValue './src/main/cpp/CMakeLists.txt' -Force
  $abis = @(@($native.abiFilters) + @('arm64-v8a', 'x86_64') | Where-Object { $_ } | Select-Object -Unique)
  $native | Add-Member -NotePropertyName abiFilters -NotePropertyValue $abis -Force
  $build.buildOption | Add-Member -NotePropertyName externalNativeOptions -NotePropertyValue $native -Force
  $mergedFiles[$buildPath] = $build | ConvertTo-Json -Depth 40
  $packagePath = 'entry/oh-package.json5'
  $package = Get-Content -LiteralPath (Join-Path $targetRoot $packagePath) -Raw -Encoding UTF8 | ConvertFrom-Json
  if (!$package.dependencies) { $package | Add-Member -NotePropertyName dependencies -NotePropertyValue ([pscustomobject]@{}) -Force }
  $package.dependencies | Add-Member -NotePropertyName 'libcapture_probe.so' -NotePropertyValue 'file:./src/main/cpp/types/libcapture_probe' -Force
  $mergedFiles[$packagePath] = $package | ConvertTo-Json -Depth 40
  $backupRoot = Join-Path $targetRoot ('update_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
  $allFiles = $files + @($mergedFiles.Keys) + @('AppScope/app.json5')
  foreach ($item in $allFiles) {
    $dst = Join-Path $targetRoot $item
    $original[$item] = Test-Path -LiteralPath $dst
    if ($original[$item]) {
      $backup = Join-Path $backupRoot $item
      New-Item -ItemType Directory -Path (Split-Path $backup) -Force | Out-Null
      Copy-Item -LiteralPath $dst -Destination $backup -Force
    }
  }
  foreach ($item in $files) {
    $dst = Join-Path $targetRoot $item
    $changed += $item
    New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $item) -Destination $dst -Force
  }
  foreach ($item in $mergedFiles.Keys) {
    $changed += $item
    [IO.File]::WriteAllText((Join-Path $targetRoot $item), $mergedFiles[$item], (New-Object Text.UTF8Encoding($false)))
  }
  $changed += 'AppScope/app.json5' 
  [IO.File]::WriteAllText($appFile, $appText, (New-Object Text.UTF8Encoding($false)))
  [System.Windows.Forms.MessageBox]::Show('1.6.1-probe 源码更新完成，旧文件已备份。请回到 DevEco 同步后重新运行。签名、包名和 SDK 配置已保留。', '更新完成') | Out-Null
} catch {
  $failure = $_.Exception.Message
  $rollbackFailed = $false
  foreach ($item in $changed) {
    try {
      $dst = Join-Path $targetRoot $item
      if ($original[$item]) { Copy-Item -LiteralPath (Join-Path $backupRoot $item) -Destination $dst -Force }
      elseif (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
    } catch { $rollbackFailed = $true }
  }
  $detail = if ($rollbackFailed) { '部分文件回退失败，请从 update_backup 文件夹恢复后再构建。' } else { '若已开始替换，文件已回退。' }
  [System.Windows.Forms.MessageBox]::Show(('更新失败：' + $failure + '。' + $detail), '更新未完成') | Out-Null
  exit 1
}
