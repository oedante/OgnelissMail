// Расширение «Поделиться» для iPhone и iPad (2.7.5, жалоба пользователей
// iPhone 27.11.2026: «через „Поделиться“ файлом или картинкой приложение не
// отображается»). Файлы, фото, видео, текст и ссылки из других приложений
// попадают в Ogneliss: расширение кладёт их в общую группу
// group.com.ogneliss.mail и открывает приложение ссылкой
// ShareMedia-com.ogneliss.mail://…; дальше — новое письмо с вложениями
// (receive_sharing_intent, lib/services/integration/share_intent_service.dart).
//
// Подключение цели в Xcode — ios/OgnelissShare/README.md.
import receive_sharing_intent

class ShareViewController: RSIShareViewController {
  // Сразу в приложение, без окна-посредника.
  override func shouldAutoRedirect() -> Bool { true }
}
