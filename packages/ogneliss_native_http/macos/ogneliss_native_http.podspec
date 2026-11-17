#
# Mac (2.6.5): прокси системы для почтовых серверов (метод proxyFor канала
# ogneliss/native_http).
#
Pod::Spec.new do |s|
  s.name             = 'ogneliss_native_http'
  s.version          = '1.0.0'
  s.summary          = 'Прокси системы для Ogneliss Mail на Mac.'
  s.description      = 'Канал ogneliss/native_http: прокси и PAC для адреса почтового сервера.'
  s.homepage         = 'https://ogneliss.ru'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'Ogneliss' => 'support@ogneliss.ru' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.15'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
