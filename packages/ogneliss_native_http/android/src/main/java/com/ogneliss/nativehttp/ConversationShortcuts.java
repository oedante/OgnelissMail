package com.ogneliss.nativehttp;

// Ярлыки бесед для уведомлений о письмах (Беседы для VIP / для всех писем),
// канал ogneliss/messenger (1.9.x; перенесено сюда из MainActivity 18.11.2026).
//
// Уведомление о письме ссылается на долгоживущий ярлык беседы с человеком
// (Person, LocusId) — Android 11+ показывает его в разделе «Беседы»: слева
// портрет отправителя со значком приложения на нём, беседу можно сделать
// приоритетной. Без ярлыка Android рисует обычный вид: значок приложения
// слева, портрет сбоку.
//
// Замечание владельца 18.11.2026 («работает, но компоновка не та — значок
// приложения сбоку от портрета»): канал регистрировался в MainActivity, то
// есть только в основном движке. Письма фоновой проверки (WorkManager,
// сигналы сервера) показывает отдельный движок — там канала не было, ярлык
// не публиковался, и уведомление выходило без беседы. Плагины пакетов
// Flutter подключает к каждому движку (как AvatarPainter) — поэтому здесь.
//
// Только системные API (ShortcutManager, android.app.Person — Android 11+,
// раньше раздела «Беседы» нет), без androidx. Ярлык — один на отправителя
// (id с «conv_» считает Dart, MessengerNotify.shortcutId); нажатие на него
// открывает последнее письмо человека тем же путём, что виджет «Почта»
// (MainActivity → WidgetBridge, extra «ogneliss_widget»).
//
// Быстрые действия значка (quick_actions) при каждом запуске заменяют все
// динамические ярлыки — беседы, уже связанные с уведомлением, Android хранит
// в кэше, а следующее письмо публикует ярлык заново. Любая ошибка — false:
// Dart покажет уведомление без беседы.

import android.app.Person;
import android.content.Context;
import android.content.Intent;
import android.content.LocusId;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.drawable.Icon;
import android.os.Build;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.List;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

final class ConversationShortcuts implements MethodChannel.MethodCallHandler {
    static final String CHANNEL = "ogneliss/messenger";
    private static final String PREFIX = "conv_";
    private static final String ACTION = "com.ogneliss.mail.CONVERSATION";
    // Тот же ключ, что WidgetBridge.EXTRA в приложении.
    private static final String EXTRA_OPEN = "ogneliss_widget";

    private final Context context;

    ConversationShortcuts(Context context) {
        this.context = context.getApplicationContext();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "pushShortcut": {
                boolean ok;
                try {
                    ok = push(call);
                } catch (Throwable e) {
                    ok = false;
                }
                result.success(ok);
                break;
            }
            case "removeShortcuts":
                try {
                    removeAll();
                } catch (Throwable ignored) {
                    // нечего снимать или система не дала — не важно
                }
                result.success(null);
                break;
            default:
                result.notImplemented();
        }
    }

    private boolean push(MethodCall call) {
        // Раздел «Беседы» — с Android 11.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false;
        String id = call.argument("id");
        String open = call.argument("open");
        String name = trim(call.argument("name"));
        String email = trim(call.argument("email"));
        if (id == null || !id.startsWith(PREFIX) || open == null || name.isEmpty()) return false;
        ShortcutManager sm = context.getSystemService(ShortcutManager.class);
        Intent launch = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (sm == null || launch == null || launch.getComponent() == null) return false;

        Icon icon = null;
        byte[] avatar = call.argument("avatar");
        if (avatar != null && avatar.length > 0) {
            Bitmap bmp = BitmapFactory.decodeByteArray(avatar, 0, avatar.length);
            if (bmp != null) icon = Icon.createWithAdaptiveBitmap(bmp);
        }
        Person.Builder person = new Person.Builder()
                .setName(name)
                .setKey(id)
                .setImportant(true);
        if (email.contains("@")) person.setUri("mailto:" + email);
        if (icon != null) person.setIcon(icon);

        Intent intent = new Intent(ACTION)
                .setComponent(launch.getComponent())
                .putExtra(EXTRA_OPEN, open);
        ShortcutInfo.Builder b = new ShortcutInfo.Builder(context, id)
                .setShortLabel(name)
                .setLongLived(true)
                .setPerson(person.build())
                .setLocusId(new LocusId(id))
                .setIntent(intent)
                // После быстрых действий значка: при нехватке места Android
                // убирает ярлык с наибольшим рангом — беседу, а не «Написать».
                .setRank(100);
        if (icon != null) b.setIcon(icon);
        // Android 13+: беседы не в меню значка (на 11–12 так скрытый ярлык
        // не публиковался бы вовсе — там он виден в меню после быстрых действий).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            b.setExcludedFromSurfaces(ShortcutInfo.SURFACE_LAUNCHER);
        }
        sm.pushDynamicShortcut(b.build());
        return true;
    }

    /** «Беседы для VIP» выключили — снять свои ярлыки (и из кэша). */
    private void removeAll() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return;
        ShortcutManager sm = context.getSystemService(ShortcutManager.class);
        if (sm == null) return;
        List<String> ids = new ArrayList<>();
        for (ShortcutInfo s : sm.getShortcuts(ShortcutManager.FLAG_MATCH_DYNAMIC | ShortcutManager.FLAG_MATCH_CACHED)) {
            if (s.getId().startsWith(PREFIX)) ids.add(s.getId());
        }
        if (!ids.isEmpty()) sm.removeLongLivedShortcuts(ids);
    }

    private static String trim(Object v) {
        return v == null ? "" : v.toString().trim();
    }
}
