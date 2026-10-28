// lib/core/network/corporate_http_client_web.dart
// Реализация для web: сертификатами управляет браузер.
import 'package:http/http.dart' as http;

http.Client createCorporateHttpClient({bool? compat}) => http.Client();
