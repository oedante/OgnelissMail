# tool/desktop/windows/multi_window.ps1
#
# Окна писем и редактора на Windows (2.5.4, lib/features/compose/compose_window.dart):
# у каждого окна desktop_multi_window свой движок Flutter, и плагины (окно,
# файлы, браузер, ссылки) в нём нужно зарегистрировать — так велит пакет
# (README desktop_multi_window, «Working with Plugins in Sub-Windows»).
# Папку windows\ создаёт `flutter create` при сборке (в git её нет), поэтому
# правка windows\runner\flutter_window.cpp — здесь. Её вызывают
# scripts\build_windows.ps1 и сборка на GitHub (.github/workflows/ci.yml).
# Повторный запуск ничего не меняет.

param([string]$Root = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
$fw = Join-Path $Root 'windows\runner\flutter_window.cpp'
if (-not (Test-Path $fw)) { throw "Нет $fw — сначала flutter create --platforms=windows" }
$full = (Resolve-Path $fw).Path
$t = [IO.File]::ReadAllText($full)
if ($t -match 'DesktopMultiWindowSetWindowCreatedCallback') {
  Write-Host 'flutter_window.cpp: плагины в окнах уже регистрируются'
  exit 0
}
$include = '#include "flutter/generated_plugin_registrant.h"'
$register = 'RegisterPlugins(flutter_controller_->engine());'
if (-not $t.Contains($include) -or -not $t.Contains($register)) {
  throw 'flutter_window.cpp не похож на шаблон Flutter — правку внести вручную (README desktop_multi_window)'
}
$nl = "`r`n"
$t = $t.Replace($include, $include + $nl + '#include "desktop_multi_window/desktop_multi_window_plugin.h"')
$callback = $register + $nl +
  '  // Ogneliss 2.5.4: plugins in desktop_multi_window windows (email and compose windows).' + $nl +
  '  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {' + $nl +
  '    auto* view_controller = reinterpret_cast<flutter::FlutterViewController*>(controller);' + $nl +
  '    RegisterPlugins(view_controller->engine());' + $nl +
  '  });'
$t = $t.Replace($register, $callback)
[IO.File]::WriteAllText($full, $t, (New-Object System.Text.UTF8Encoding $false))
Write-Host 'flutter_window.cpp: плагины регистрируются и в окнах писем и редактора'
