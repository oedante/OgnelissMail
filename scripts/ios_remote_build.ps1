<#
.SYNOPSIS
  Сборка iOS из Windows (Android Studio) на Mac по SSH.

.DESCRIPTION
  iOS-приложение собирается только Xcode на macOS — из Windows напрямую
  нельзя. Скрипт копирует проект на Mac, запускает там scripts/build_ios.sh и
  забирает готовый IPA в build\ios\ipa\ на Windows.

  Один раз:
    1. На Mac: Системные настройки → Основные → Общий доступ → «Удалённый вход» (SSH).
    2. На Mac установить Xcode, Flutter 3.38+, CocoaPods (docs/guides/BUILD_IOS.md).
    3. На Windows: ssh-keygen; затем
         type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh user@mac "cat >> ~/.ssh/authorized_keys"
    4. Заполнить scripts\ios_remote.json (пример — scripts\ios_remote.example.json).

.EXAMPLE
  .\scripts\ios_remote_build.ps1            # IPA
  .\scripts\ios_remote_build.ps1 -Upload    # IPA и выгрузка в TestFlight
  .\scripts\ios_remote_build.ps1 -Check     # проверить окружение Mac
#>
param([switch]$Upload, [switch]$Check)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$cfgPath = Join-Path $PSScriptRoot 'ios_remote.json'
if (-not (Test-Path $cfgPath)) {
  Write-Host "Нет scripts\ios_remote.json — скопируйте scripts\ios_remote.example.json и заполните." -ForegroundColor Red
  exit 1
}
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$target = "$($cfg.user)@$($cfg.host)"
$dir = if ($cfg.remoteDir) { $cfg.remoteDir } else { 'ogneliss-mail' }

Write-Host "== Mac: $target, каталог ~/$dir"
ssh -o BatchMode=yes $target "echo ok" | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host 'Нет SSH-доступа к Mac (см. описание скрипта).' -ForegroundColor Red; exit 1 }

Write-Host '== Копирование проекта'
# tar есть в Windows 10/11. Без сборок, кэшей и Pods — только исходники.
$excl = @('--exclude=./build', '--exclude=./.dart_tool', '--exclude=./.git', '--exclude=./ios/Pods',
          '--exclude=./ios/.symlinks', '--exclude=./android/.gradle', '--exclude=./android/app/build',
          '--exclude=./packages/*/.dart_tool', '--exclude=./packages/*/build', '--exclude=*/node_modules',
          # Настройки Xcode на Mac (Team, App Groups, цель виджетов) не затираем:
          # файл проекта там свой, новый — из project.pbxproj.base (build_ios.sh).
          '--exclude=./ios/Runner.xcodeproj/project.pbxproj', '--exclude=./ios/Runner/Runner.entitlements',
          '--exclude=./ios/Flutter/Signing.xcconfig', '--exclude=./ios/Runner.xcworkspace/contents.xcworkspacedata',
          '--exclude=*/xcuserdata')
$tmp = Join-Path $env:TEMP 'ogneliss-ios.tgz'
tar -czf $tmp @excl -C $Root .
if ($LASTEXITCODE -ne 0) { throw 'tar не смог упаковать проект' }
scp -q $tmp "${target}:/tmp/ogneliss-ios.tgz"
ssh $target "mkdir -p ~/$dir && tar -xzf /tmp/ogneliss-ios.tgz -C ~/$dir && rm /tmp/ogneliss-ios.tgz"
Remove-Item $tmp

$buildArgs = if ($Check) { '--check' } elseif ($Upload) { '--upload' } else { '' }
$envs = @("export LANG=en_US.UTF-8", 'export PATH="$HOME/flutter/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"')
if ($cfg.teamId) { $envs += "export TEAM_ID=$($cfg.teamId)" }
if ($cfg.ascKeyId) { $envs += "export ASC_KEY_ID=$($cfg.ascKeyId)"; $envs += "export ASC_ISSUER_ID=$($cfg.ascIssuerId)" }
if ($cfg.keychainPassword) { $envs += "export KEYCHAIN_PASSWORD='$($cfg.keychainPassword)'" }
$remote = ($envs -join '; ') + "; cd ~/$dir && bash scripts/build_ios.sh $buildArgs"

Write-Host "== Сборка на Mac (scripts/build_ios.sh $buildArgs)"
ssh -t $target $remote
if ($LASTEXITCODE -ne 0) { Write-Host 'Сборка на Mac не удалась — подробности выше.' -ForegroundColor Red; exit 1 }
if ($Check) { exit 0 }

Write-Host '== Забираю IPA'
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'build\ios\ipa') | Out-Null
scp -q "${target}:~/$dir/build/ios/ipa/*.ipa" (Join-Path $Root 'build\ios\ipa\')
Get-ChildItem (Join-Path $Root 'build\ios\ipa') -Filter *.ipa | ForEach-Object { Write-Host "Готово: $($_.FullName)" -ForegroundColor Green }
