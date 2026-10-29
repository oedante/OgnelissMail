#
# Режим совместимости со шлюзом на iPhone (1.6.12): запросы к Exchange через
# сетевой стек iOS (NSURLSession), как у штатной Почты.
#
Pod::Spec.new do |s|
  s.name             = 'ogneliss_native_http'
  s.version          = '1.0.0'
  s.summary          = 'HTTP через сетевой стек системы для Ogneliss Mail.'
  s.description      = 'Канал ogneliss/native_http: запросы к почтовому серверу через NSURLSession.'
  s.homepage         = 'https://ogneliss.ru'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'Ogneliss' => 'support@ogneliss.ru' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
