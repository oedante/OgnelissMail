<#
.SYNOPSIS
  Движок перевода для Windows (2.2.0): Bergamot Translator из npm.

.DESCRIPTION
  То же, что tool/bergamot/fetch_engine.sh, для компьютера владельца
  (scripts/build_windows.ps1 запускает его перед flutter build windows):
  @browsermt/bergamot-translator (MPL-2.0) → build\bergamot, откуда
  tool/bergamot/bergamot.cmake кладёт его рядом с exe (data\bergamot).
  Пакет и файлы сверяются с tool/bergamot/engine.sha256; другой файл —
  ошибка. Нужен tar.exe (есть в Windows 10 1803 и новее).

.EXAMPLE
  .\tool\bergamot\fetch_engine.ps1
  .\tool\bergamot\fetch_engine.ps1 -From C:\Downloads\bergamot-translator-0.4.9.tgz
#>
param([string]$From = '')

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent (Split-Path -Parent $Here)
$Out = Join-Path $Root 'build\bergamot'
$sums = @{}
Get-Content (Join-Path $Here 'engine.sha256') | ForEach-Object {
  $p = $_.Trim() -split '\s+', 2
  if ($p.Count -eq 2) { $sums[$p[1]] = $p[0].ToLower() }
}
$tgzName = ($sums.Keys | Where-Object { $_ -like '*.tgz' } | Select-Object -First 1)
$version = $tgzName -replace '^bergamot-translator-', '' -replace '\.tgz$', ''
$files = $sums.Keys | Where-Object { $_ -like 'package/*' }

function Sha([string]$path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower() }

function Complete {
  foreach ($f in $files) {
    $p = Join-Path $Out ($f.Substring(8) -replace '/', '\')
    if (-not (Test-Path $p) -or (Sha $p) -ne $sums[$f]) { return $false }
  }
  return (Test-Path (Join-Path $Out 'LICENSE-MPL-2.0.txt')) -and (Test-Path (Join-Path $Out 'THIRD-PARTY-NOTICES.txt'))
}

if (Complete) { Write-Host "Bergamot ${version}: уже на месте ($Out)"; exit 0 }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ogn-bergamot-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
  $tgz = Join-Path $tmp $tgzName
  if ($From) {
    Copy-Item -LiteralPath $From -Destination $tgz
  } else {
    $url = "https://registry.npmjs.org/@browsermt/bergamot-translator/-/$tgzName"
    Write-Host "Bergamot ${version}: $url"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    for ($i = 1; ; $i++) {
      try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tgz; break }
      catch { if ($i -ge 4) { throw }; Start-Sleep -Seconds (2 * $i) }
    }
  }
  if ((Sha $tgz) -ne $sums[$tgzName]) { throw "Bergamot: sha256 пакета не совпал" }
  $x = Join-Path $tmp 'x'
  New-Item -ItemType Directory -Force -Path $x | Out-Null
  & tar -xzf $tgz -C $x
  if ($LASTEXITCODE -ne 0) { throw "Bergamot: tar не распаковал пакет" }
  $stage = "$Out.tmp"
  if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
  New-Item -ItemType Directory -Force -Path (Join-Path $stage 'worker') | Out-Null
  foreach ($f in $files) {
    $src = Join-Path $x ($f -replace '/', '\')
    if ((Sha $src) -ne $sums[$f]) { throw "Bergamot: sha256 $f не совпал" }
    Copy-Item -LiteralPath $src -Destination (Join-Path $stage ($f.Substring(8) -replace '/', '\'))
  }
  Copy-Item (Join-Path $Here 'LICENSE-MPL-2.0.txt'), (Join-Path $Here 'THIRD-PARTY-NOTICES.txt') -Destination $stage
  if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
  Move-Item -LiteralPath $stage -Destination $Out
  Write-Host "Bergamot ${version}: $Out"
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
