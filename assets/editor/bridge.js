// Мост редактора писем (HugeRTE) с приложением.
//
// Настройки — в <script type="application/json" id="ogn-config"> (не
// исполняется). Приложение → редактор: window.OgnEditor.set/insert/get/focus
// через evaluateJavascript (строки передаются как JSON — без ручного
// экранирования). Редактор → приложение: обработчики flutter_inappwebview
// ready / change / pickImage / failed.
(function () {
  'use strict';
  var cfg = {};
  try {
    cfg = JSON.parse(document.getElementById('ogn-config').textContent || '{}');
  } catch (e) {}

  var queue = [];
  var bridgeReady = false;
  function flush() {
    if (!window.flutter_inappwebview || !window.flutter_inappwebview.callHandler) return;
    bridgeReady = true;
    while (queue.length) {
      var m = queue.shift();
      try { window.flutter_inappwebview.callHandler(m[0], m[1]); } catch (e) {}
    }
  }
  function send(name, arg) {
    queue.push([name, arg === undefined ? null : arg]);
    if (bridgeReady || window.flutter_inappwebview) flush();
  }
  window.addEventListener('flutterInAppWebViewPlatformReady', flush);

  var ed = null;
  var timer = null;
  var lastSent = null;
  function changed() {
    if (timer) clearTimeout(timer);
    timer = setTimeout(function () {
      timer = null;
      if (!ed) return;
      var html = ed.getContent();
      if (html === lastSent) return;
      lastSent = html;
      send('change', html);
    }, 350);
  }

  window.OgnEditor = {
    set: function (html) {
      if (!ed) return;
      ed.setContent(html || '');
      ed.undoManager.clear();
      ed.undoManager.add();
      lastSent = ed.getContent();
    },
    insert: function (html) {
      if (!ed) return;
      ed.insertContent(html || '');
      changed();
    },
    append: function (html) {
      if (!ed) return;
      ed.setContent(ed.getContent() + (html || ''));
      changed();
    },
    // Команда оформления из меню выделения (жирный, курсив, подчёркнутый,
    // без оформления, отмена). Повторное применение снимает оформление.
    exec: function (cmd) {
      if (!ed) return;
      var allowed = { Bold: 1, Italic: 1, Underline: 1, RemoveFormat: 1, Undo: 1, Redo: 1 };
      if (!allowed[cmd]) return;
      ed.focus();
      ed.execCommand(cmd);
      changed();
    },
    get: function () { return ed ? ed.getContent() : ''; },
    focus: function () { if (ed) ed.focus(); },
    // Фокус ушёл в поле приложения (тема, адресаты): убрать курсор и
    // выделение из окна редактора — иначе курсоров видно два.
    blur: function () {
      try {
        // Текст редактора — во внутреннем фрейме: выделение и фокус — его.
        var w = ed && ed.getWin ? ed.getWin() : null;
        var inner = w && w.getSelection ? w.getSelection() : null;
        if (inner) inner.removeAllRanges();
        if (ed && ed.getBody()) ed.getBody().blur();
        if (w && w.blur) w.blur();
        var sel = window.getSelection && window.getSelection();
        if (sel) sel.removeAllRanges();
        if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
      } catch (e) {}
    },
    // Окно редактора сдвинулось на экране (лист прокрутили, над редактором
    // появилась или исчезла строка), а «капля» Android под курсором осталась
    // на прежнем месте: печатаешь в одной строке, а капля — в другой
    // (замечание 27.10.2026). Выделение переустанавливается — капля прячется,
    // курсор остаётся там, где идёт ввод; следующее касание покажет её верно.
    refreshSelection: function () {
      try {
        if (!ed || !ed.hasFocus()) return;
        var w = ed.getWin();
        var s = w && w.getSelection ? w.getSelection() : null;
        if (!s || !s.rangeCount) return;
        var r = s.getRangeAt(0).cloneRange();
        s.removeAllRanges();
        (w.requestAnimationFrame || setTimeout)(function () {
          try { s.addRange(r); } catch (e) {}
        });
      } catch (e) {}
    },
    // Приветствие (абзац #ogn-greeting) меняется вслед за получателями, но
    // только пока пользователь его не правил: текст должен совпадать с
    // прежним автоматическим. previous == null — вариант выбран кнопкой
    // «Приветствие»: строка заменяется в любом случае, а если её нет
    // (выбирали «Без приветствия» или стёрли) — вставляется первой.
    // Пустой text — блок убирается.
    setGreeting: function (text, previous) {
      if (!ed) return;
      var body = ed.getBody();
      var el = body.querySelector('#ogn-greeting');
      if (el && previous != null) {
        var cur = (el.textContent || '').replace(/\u00a0/g, ' ').trim();
        if (cur !== String(previous).trim()) return;
      }
      if (!text) {
        if (el && el.parentNode) el.parentNode.removeChild(el);
        changed();
        return;
      }
      if (!el) {
        if (previous != null && String(previous).trim() !== '') return;
        body.insertAdjacentHTML('afterbegin', '<div id="ogn-greeting"></div>');
        el = body.querySelector('#ogn-greeting');
        if (!el) return;
      }
      el.textContent = text;
      changed();
    },
    // Подпись (блок #ogn-signature) — замена при смене ящика «От».
    setSignature: function (html) {
      if (!ed) return;
      var el = ed.getBody().querySelector('#ogn-signature');
      if (!el) {
        if (!html) return;
        ed.getBody().insertAdjacentHTML('beforeend', '<div><br></div><div id="ogn-signature">' + html + '</div>');
      } else if (!html) {
        el.parentNode.removeChild(el);
      } else {
        el.innerHTML = html;
      }
      changed();
    },
    // Панель форматирования: на телефоне по умолчанию скрыта (шрифт задан
    // стилем аккаунта), открывается кнопкой «Aa» на экране письма.
    toolbar: function (show) {
      document.documentElement.classList.toggle('ogn-notoolbar', !show);
      // Панель, скрытая при запуске, пересчитывает ширину кнопок (иначе часть
      // кнопок пряталась в «…» по размеру, измеренному скрытой).
      if (show) window.dispatchEvent(new Event('resize'));
    },
    // Стиль текста аккаунта (шрифт, размер) — при смене ящика «От».
    setBodyStyle: function (css) {
      if (!ed) return;
      ed.getBody().setAttribute('style', css || '');
    },
    // Курсор — на среднюю из трёх пустых строк после приветствия.
    focusText: function () {
      if (!ed) return;
      ed.focus();
      var g = ed.getBody().querySelector('#ogn-greeting');
      var first = g ? g.nextElementSibling : ed.getBody().firstChild;
      var target = first && first.nextElementSibling && first.nextElementSibling.id !== 'ogn-signature'
        ? first.nextElementSibling : first;
      if (target) {
        try {
          // Быстрый ответ уже вставлен — курсор в конец его текста.
          if (target.textContent && target.textContent.trim()) {
            ed.selection.select(target, true);
            ed.selection.collapse(false);
          } else {
            ed.selection.setCursorLocation(target, 0);
          }
        } catch (e) {}
      }
    },
  };

  var dark = !!cfg.dark;
  var plugins = 'lists advlist link autolink table charmap searchreplace';
  // Самое нужное — первым: остальное уходит в «…» (sliding).
  var toolbar = 'bold italic underline forecolor | bullist numlist | link ognimage | ' +
    'removeformat undo redo | backcolor fontsize blocks | alignleft aligncenter alignright | ' +
    'outdent indent table | charmap searchreplace';

  try {
    hugerte.init({
      selector: '#ogn-editor',
      language: cfg.lang && cfg.lang !== 'en' ? cfg.lang : undefined,
      skin: false,
      content_css: false,
      content_style: (cfg.contentCss || '') + (cfg.extraCss || ''),
      height: '100%',
      resize: false,
      menubar: false,
      statusbar: false,
      promotion: false,
      branding: false,
      plugins: plugins,
      toolbar: toolbar,
      toolbar_mode: 'sliding',
      toolbar_sticky: true,
      contextmenu: false,
      browser_spellcheck: true,
      placeholder: cfg.placeholder || '',
      // Ссылки и адреса — как есть, без «относительных» путей от about:blank.
      convert_urls: false,
      relative_urls: false,
      remove_script_host: false,
      link_assume_external_targets: 'https',
      link_target_list: false,
      link_title: false,
      // Безопасность: очистка DOMPurify, внедрённые объекты — в безопасный вид,
      // фреймы — в песочнице. Скрипты из текста письма не выполняются.
      xss_sanitization: true,
      convert_unsafe_embeds: true,
      sandbox_iframes: true,
      allow_script_urls: false,
      // Вставка: картинки из буфера — встроенными (data:), без загрузки.
      paste_data_images: true,
      automatic_uploads: false,
      images_file_types: 'jpeg,jpg,png,gif,webp,bmp',
      table_default_styles: { 'border-collapse': 'collapse', width: '100%' },
      table_default_attributes: { border: '1', cellpadding: '4' },
      // Строки — блоками div, как в Gmail и Outlook: у получателя нет лишних
      // отступов абзацев, и письмо выглядит так же, как при наборе.
      forced_root_block: 'div',
      font_size_formats: '8pt 9pt 10pt 11pt 12pt 14pt 16pt 18pt 24pt 36pt',
      setup: function (editor) {
        ed = editor;
        editor.ui.registry.addButton('ognimage', {
          icon: 'image',
          tooltip: cfg.imageTooltip || 'Image',
          onAction: function () { send('pickImage'); },
        });
        // Сочетания клавиш компьютера и клавиатуры планшета (1.8.13):
        // Ctrl+Enter (⌘+Enter на Mac) — отправить, Ctrl+S — сохранить
        // черновик. Клавиши во встроенном браузере до приложения не доходят.
        editor.addShortcut('meta+13', '', function () { send('key', 'send'); });
        editor.addShortcut('meta+83', '', function () { send('key', 'save'); });
        editor.on('init', function () {
          if (cfg.bodyStyle) editor.getBody().setAttribute('style', cfg.bodyStyle);
          lastSent = editor.getContent();
          send('ready');
        });
        editor.on('input change undo redo keyup paste ExecCommand SetContent', changed);
        // Курсор ушёл в текст письма — приложение завершает ввод в шапке
        // (адрес становится плашкой, курсор поля гаснет), 1.6.2.
        editor.on('focus', function () { send('focus'); });
        // Касание текста, когда документ редактора и так в фокусе (курсор
        // успели перенести в тему): событие focus не приходит, и курсоров
        // было два — в теме и в тексте (27.10.2026). Касание сообщает о
        // фокусе само, не чаще раза в полсекунды.
        var lastTouch = 0;
        editor.on('touchstart mousedown', function () {
          var now = Date.now();
          if (now - lastTouch < 500) return;
          lastTouch = now;
          send('focus');
        });
      },
    }).catch(function (e) { send('failed', String(e)); });
  } catch (e) {
    send('failed', String(e));
  }
  if (dark) document.documentElement.classList.add('ogn-dark');
  if (cfg.toolbarHidden) document.documentElement.classList.add('ogn-notoolbar');
})();
