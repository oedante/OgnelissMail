// ios/OgnelissWidgets/OgnelissWidgets.swift
// Виджеты iPhone: «Мой день», «Почта», «Календарь», «Заметки» — те же, что
// на Android (HomeWidgets.kt). Данные готовит приложение
// (lib/services/home_widget_service.dart) и кладёт JSON с уже переведёнными
// строками в общий контейнер App Group «group.com.ogneliss.mail»
// (WidgetBridgePlugin.swift). Расширение только рисует: прошедшее прячет
// само по времени окончания, поэтому между обновлениями виджет не устаревает.
// Нажатие — ссылка com.ogneliss.mail://widget?t=<экран>.
//
// Как подключить цель в Xcode — ios/OgnelissWidgets/README.md.

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Данные

private let appGroup = "group.com.ogneliss.mail"

private func loadJSON(_ key: String) -> [String: Any]? {
  guard let raw = UserDefaults(suiteName: appGroup)?.string(forKey: key),
        let data = raw.data(using: .utf8),
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else { return nil }
  return obj
}

private extension Dictionary where Key == String, Value == Any {
  func str(_ k: String) -> String { (self[k] as? String) ?? "" }
  func ms(_ k: String) -> Date {
    let v = (self[k] as? NSNumber)?.doubleValue ?? 0
    return Date(timeIntervalSince1970: v / 1000)
  }
  func items(_ k: String) -> [[String: Any]] { (self[k] as? [[String: Any]]) ?? [] }
}

private func widgetURL(_ type: String) -> URL {
  var c = URLComponents()
  c.scheme = "com.ogneliss.mail"
  c.host = "widget"
  c.queryItems = [URLQueryItem(name: "t", value: type)]
  return c.url ?? URL(string: "com.ogneliss.mail://widget")!
}

// MARK: - Цвета (спокойные, как на Android)

private func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
  func ui(_ v: UInt32) -> UIColor {
    UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
  }
  return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
}

// Фон — как подложка «Мой день» в приложении (чисто белый выделялся, 10.10.2026).
private let cBg = dyn(0xE6EBF2, 0x181D23)
private let cText = dyn(0x1F2329, 0xE2E4E8)
private let cSub = dyn(0x5B6470, 0x9AA3AE)
private let cAccent = dyn(0x2A63A6, 0x8AB1E6)
// «Не обновлялось с …» (1.6.48) — как на Android.
private let cWarn = dyn(0x7A5E00, 0xE0B03A)

private func argb(_ v: NSNumber?) -> Color {
  let x = UInt32(truncatingIfNeeded: v?.int64Value ?? 0xFF5C7CFA)
  return Color(red: Double((x >> 16) & 0xFF) / 255, green: Double((x >> 8) & 0xFF) / 255,
               blue: Double(x & 0xFF) / 255)
}

/// Тема виджетов (1.7.0, настройка приложения «Тема виджетов»): «1» —
/// светлая, «2» — тёмная, иначе — как у телефона. Приложение кладёт значение
/// в общий контейнер App Group (ключ widget_theme).
private func forcedWidgetScheme() -> ColorScheme? {
  switch UserDefaults(suiteName: appGroup)?.string(forKey: "widget_theme") {
  case "1": return .light
  case "2": return .dark
  default: return nil
  }
}

/// Фон виджета: iOS 17 требует containerBackground, раньше — обычный фон.
/// Цвета виджетов (dyn) зависят от темы — при выбранной в приложении теме
/// она подставляется виджету вместо темы телефона.
private struct WidgetBackground: ViewModifier {
  func body(content: Content) -> some View {
    themed(filled(content))
  }

  @ViewBuilder
  private func filled(_ content: Content) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      content.containerBackground(for: .widget) { cBg }
    } else {
      content.padding(12).background(cBg)
    }
  }

  @ViewBuilder
  private func themed<V: View>(_ v: V) -> some View {
    if let scheme = forcedWidgetScheme() {
      v.environment(\.colorScheme, scheme)
    } else {
      v
    }
  }
}

private extension View {
  func widgetBackground() -> some View { modifier(WidgetBackground()) }
}

// MARK: - Общая лента обновлений

struct JSONEntry: TimelineEntry {
  let date: Date
  let json: [String: Any]?
  /// «Календарь: месяц» (iOS 17+): показанный месяц и выбранный день.
  var anchor: Date? = nil
  var selected: Date? = nil
}

/// Записи на «сейчас» и на моменты окончания ближайших встреч (прошедшее
/// исчезает вовремя); дальше система спросит снова через 30 минут.
struct JSONProvider: TimelineProvider {
  let key: String

  func placeholder(in context: Context) -> JSONEntry { JSONEntry(date: Date(), json: nil) }

  func getSnapshot(in context: Context, completion: @escaping (JSONEntry) -> Void) {
    completion(JSONEntry(date: Date(), json: loadJSON(key)))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<JSONEntry>) -> Void) {
    let now = Date()
    let json = loadJSON(key)
    var dates = [now]
    for item in json?.items("items") ?? [] {
      for k in ["end", "st"] where item[k] != nil {
        let d = item.ms(k)
        if d > now && d < now.addingTimeInterval(6 * 3600) { dates.append(d) }
      }
    }
    let entries = Array(Set(dates)).sorted().prefix(12).map { JSONEntry(date: $0, json: json) }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
  }
}

// MARK: - Общие части

private struct Header: View {
  let title: String
  let sub: String
  let action: String
  let actionIcon: String
  var body: some View {
    HStack(spacing: 8) {
      Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(cAccent).lineLimit(1)
      Text(sub).font(.system(size: 13)).foregroundColor(cSub).lineLimit(1)
      Spacer(minLength: 4)
      Link(destination: widgetURL(action)) {
        Image(systemName: actionIcon).font(.system(size: 16, weight: .semibold)).foregroundColor(cAccent)
          .frame(width: 28, height: 28)
      }
    }
  }
}

private func dayLabel(_ d: Date, _ json: [String: Any], _ fmt: DateFormatter) -> String {
  let cal = Calendar.current
  if cal.isDateInToday(d) { return json.str("today") }
  if cal.isDateInTomorrow(d) { return json.str("tomorrow") }
  return fmt.string(from: d)
}

private func dateFormatter(_ lang: String) -> DateFormatter {
  let f = DateFormatter()
  if !lang.isEmpty { f.locale = Locale(identifier: lang) }
  f.setLocalizedDateFormatFromTemplate("EEEdMMM")
  return f
}

private func rowsFor(_ family: WidgetFamily, small: Int, medium: Int, large: Int) -> Int {
  switch family {
  case .systemSmall: return small
  case .systemLarge: return large
  default: return medium
  }
}

// MARK: - «Мой день»

struct MyDayView: View {
  let entry: JSONEntry
  @Environment(\.widgetFamily) var family

  var body: some View {
    let j = entry.json ?? [:]
    let fmt = dateFormatter(j.str("lang"))
    let items = j.items("items").filter { $0.ms("end") > entry.date }
    let max = rowsFor(family, small: 3, medium: 3, large: 9)
    VStack(alignment: .leading, spacing: 4) {
      Header(title: j.str("title").isEmpty ? "Ogneliss" : j.str("title"),
             sub: fmt.string(from: entry.date), action: "compose", actionIcon: "square.and.pencil")
      if entry.json == nil {
        Text(NSLocalizedString("open_app", comment: "")).font(.system(size: 13)).foregroundColor(cSub)
      } else if items.isEmpty {
        Text(j.str("empty")).font(.system(size: 13)).foregroundColor(cSub)
      }
      ForEach(Array(items.prefix(max).enumerated()), id: \.offset) { _, it in
        HStack(spacing: 8) {
          Text(it.str("t")).font(.system(size: 13)).foregroundColor(cAccent).frame(width: 48, alignment: .leading)
          Text(it.str("s")).font(.system(size: 14)).foregroundColor(cText).lineLimit(1)
        }
      }
      Spacer(minLength: 0)
      let footer = [j.str("unread"), j.str("work")].filter { !$0.isEmpty }.joined(separator: " · ")
      if !footer.isEmpty {
        Text(footer).font(.system(size: 12)).foregroundColor(cSub).lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .widgetURL(widgetURL("myday"))
    .widgetBackground()
  }
}

struct MyDayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "OgnelissMyDay", provider: JSONProvider(key: "widget_myday")) {
      MyDayView(entry: $0)
    }
    .configurationDisplayName(NSLocalizedString("myday_label", comment: ""))
    .description(NSLocalizedString("myday_desc", comment: ""))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

// MARK: - «Почта»

/// «Обновлено в 15:40» / «Не обновлялось с 15:40» (1.6.48): когда почта
/// обновлялась, по данным приложения; давно — по staleAt (считает
/// приложение по интервалам ящиков) на момент показа записи.
private func updatedText(_ j: [String: Any], now: Date) -> (String, Bool)? {
  guard let n = j["upd"] as? NSNumber, n.doubleValue > 0 else { return nil }
  let upd = Date(timeIntervalSince1970: n.doubleValue / 1000)
  let lang = j.str("lang")
  let tf = DateFormatter()
  if !lang.isEmpty { tf.locale = Locale(identifier: lang) }
  tf.dateStyle = .none
  tf.timeStyle = .short
  let today = Calendar.current.isDate(upd, inSameDayAs: now)
  var stamp = tf.string(from: upd)
  if !today {
    let df = DateFormatter()
    if !lang.isEmpty { df.locale = Locale(identifier: lang) }
    df.setLocalizedDateFormatFromTemplate("dMMM")
    stamp = df.string(from: upd) + ", " + stamp
  }
  let staleAt = (j["staleAt"] as? NSNumber)?.doubleValue ?? 0
  let stale = staleAt > 0 && now.timeIntervalSince1970 * 1000 > staleAt
  let text: String
  if stale {
    text = j.str("updStale").replacingOccurrences(of: "{time}", with: stamp)
  } else if today {
    text = j.str("updAt").replacingOccurrences(of: "{time}", with: stamp)
  } else {
    text = j.str("updOn").replacingOccurrences(of: "{date}", with: stamp)
  }
  return text.isEmpty ? nil : (text, stale)
}

struct MailView: View {
  let entry: JSONEntry
  @Environment(\.widgetFamily) var family

  var body: some View {
    let j = entry.json ?? [:]
    let items = j.items("items")
    let max = rowsFor(family, small: 2, medium: 3, large: 4)
    VStack(alignment: .leading, spacing: 5) {
      Header(title: j.str("title").isEmpty ? "Mail" : j.str("title"), sub: j.str("count"),
             action: "compose", actionIcon: "square.and.pencil")
      if entry.json == nil {
        Text(NSLocalizedString("open_app", comment: "")).font(.system(size: 13)).foregroundColor(cSub)
      } else if items.isEmpty {
        Text(j.str("empty")).font(.system(size: 13)).foregroundColor(cSub)
      }
      ForEach(Array(items.prefix(max).enumerated()), id: \.offset) { _, it in
        Link(destination: widgetURL(it.str("open"))) {
          if family == .systemSmall {
            VStack(alignment: .leading, spacing: 0) {
              Text(it.str("f")).font(.system(size: 13, weight: .bold)).foregroundColor(cText).lineLimit(1)
              Text(it.str("s")).font(.system(size: 12)).foregroundColor(cSub).lineLimit(1)
            }
          } else {
            HStack(spacing: 8) {
              Text(it.str("f")).font(.system(size: 14, weight: .bold)).foregroundColor(cText).lineLimit(1)
                .frame(maxWidth: 110, alignment: .leading)
              Text(it.str("s")).font(.system(size: 14)).foregroundColor(cText).lineLimit(1)
              Spacer(minLength: 4)
              Text(it.str("t")).font(.system(size: 12)).foregroundColor(cSub)
            }
          }
        }
      }
      Spacer(minLength: 0)
      if family != .systemSmall, let u = updatedText(j, now: entry.date) {
        Text(u.0).font(.system(size: 12, weight: u.1 ? .semibold : .regular))
          .foregroundColor(u.1 ? cWarn : cSub).lineLimit(1)
      }
      if family != .systemSmall && !j.str("accounts").isEmpty {
        Text(j.str("accounts")).font(.system(size: 12)).foregroundColor(cSub).lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .widgetURL(widgetURL("mail"))
    .widgetBackground()
  }
}

struct MailWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "OgnelissMail", provider: JSONProvider(key: "widget_mail")) {
      MailView(entry: $0)
    }
    .configurationDisplayName(NSLocalizedString("mail_label", comment: ""))
    .description(NSLocalizedString("mail_desc", comment: ""))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

// MARK: - «Календарь»

struct CalendarView: View {
  let entry: JSONEntry
  @Environment(\.widgetFamily) var family

  var body: some View {
    let j = entry.json ?? [:]
    let fmt = dateFormatter(j.str("lang"))
    let now = entry.date
    let items = j.items("items").filter { $0.ms("end") > now }
    let max = rowsFor(family, small: 3, medium: 3, large: 8)
    let join = items.first { !$0.str("join").isEmpty && $0.ms("st").timeIntervalSince(now) <= 15 * 60 }
    let startOfToday = Calendar.current.startOfDay(for: now)
    VStack(alignment: .leading, spacing: 3) {
      Header(title: j.str("title").isEmpty ? "Calendar" : j.str("title"),
             sub: family == .systemSmall ? "" : fmt.string(from: now), action: "event", actionIcon: "plus")
      if let jn = join, let url = URL(string: jn.str("join")) {
        Link(destination: url) {
          Text(verbatim: "▶ \(j.str("joinLabel")) · \(jn.str("t")) \(jn.str("s"))")
            .font(.system(size: 13, weight: .bold)).foregroundColor(.white).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(cAccent))
        }
      }
      if entry.json == nil {
        Text(NSLocalizedString("open_app", comment: "")).font(.system(size: 13)).foregroundColor(cSub)
      } else if items.isEmpty {
        Text(j.str("empty")).font(.system(size: 13)).foregroundColor(cSub)
      }
      let shown = Array(items.prefix(max))
      ForEach(Array(shown.enumerated()), id: \.offset) { i, it in
        let day = Swift.max(Calendar.current.startOfDay(for: it.ms("day")), startOfToday)
        let prevDay = i == 0 ? nil : Swift.max(Calendar.current.startOfDay(for: shown[i - 1].ms("day")), startOfToday)
        if prevDay != day {
          Text(dayLabel(day, j, fmt)).font(.system(size: 12, weight: .bold)).foregroundColor(cSub)
            .padding(.top, i == 0 ? 2 : 4)
        }
        Link(destination: widgetURL(it.str("open"))) {
          HStack(spacing: 6) {
            Circle().fill(argb(it["c"] as? NSNumber)).frame(width: 7, height: 7)
            Text(it.str("t")).font(.system(size: 13)).foregroundColor(cAccent)
              .frame(width: family == .systemSmall ? 40 : 48, alignment: .leading)
            Text(it.str("s")).font(.system(size: 14)).foregroundColor(cText).lineLimit(1)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .widgetURL(widgetURL("calendar"))
    .widgetBackground()
  }
}

struct CalendarWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "OgnelissCalendar", provider: JSONProvider(key: "widget_calendar")) {
      CalendarView(entry: $0)
    }
    .configurationDisplayName(NSLocalizedString("cal_label", comment: ""))
    .description(NSLocalizedString("cal_desc", comment: ""))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

// MARK: - «Заметки»

struct NotesView: View {
  let entry: JSONEntry
  @Environment(\.widgetFamily) var family

  var body: some View {
    let j = entry.json ?? [:]
    let items = j.items("items")
    let max = rowsFor(family, small: 2, medium: 2, large: 5)
    VStack(alignment: .leading, spacing: 6) {
      Header(title: j.str("title").isEmpty ? "Notes" : j.str("title"), sub: j.str("count"),
             action: "newnote", actionIcon: "plus")
      if entry.json == nil {
        Text(NSLocalizedString("open_app", comment: "")).font(.system(size: 13)).foregroundColor(cSub)
      } else if items.isEmpty {
        Text(j.str("empty")).font(.system(size: 13)).foregroundColor(cSub)
      }
      ForEach(Array(items.prefix(max).enumerated()), id: \.offset) { _, it in
        Link(destination: widgetURL(it.str("open"))) {
          VStack(alignment: .leading, spacing: 1) {
            Text(it.str("s")).font(.system(size: 14, weight: .bold)).foregroundColor(cText).lineLimit(1)
            if !it.str("p").isEmpty {
              Text(it.str("p")).font(.system(size: 12)).foregroundColor(cSub).lineLimit(1)
            }
          }
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .widgetURL(widgetURL("notes"))
    .widgetBackground()
  }
}

struct NotesWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "OgnelissNotes", provider: JSONProvider(key: "widget_notes")) {
      NotesView(entry: $0)
    }
    .configurationDisplayName(NSLocalizedString("notes_label", comment: ""))
    .description(NSLocalizedString("notes_desc", comment: ""))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

// MARK: - «Календарь: неделя» и «Календарь: месяц» (10.10.2026)
//
// Как на Android (вид «Неделя» и «Месяц» виджета календаря). Переключать
// вид кнопками внутри виджета iPhone умеет только с iOS 17 (AppIntents),
// поэтому здесь это два отдельных виджета — выбираются при добавлении.
// Данные — массив «events» того же JSON (с начала прошлого месяца на три
// месяца вперёд, включая прошедшие встречи).

private struct CalEv {
  let st: Date
  let en: Date
  let allDay: Bool
  let title: String
  let color: Color
}

private func calEvents(_ j: [String: Any]) -> [CalEv] {
  j.items("events").map {
    CalEv(st: $0.ms("st"), en: $0.ms("en"), allDay: ($0["a"] as? NSNumber)?.intValue == 1,
          title: $0.str("s"), color: argb($0["c"] as? NSNumber))
  }.sorted { ($0.allDay ? 0 : 1, $0.st) < ($1.allDay ? 0 : 1, $1.st) }
}

private func calendarFor(_ lang: String) -> Calendar {
  var c = Calendar.current
  if !lang.isEmpty { c.locale = Locale(identifier: lang) }
  return c
}

private func events(_ evs: [CalEv], on day: Date, _ cal: Calendar) -> [CalEv] {
  let start = cal.startOfDay(for: day)
  guard let next = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
  return evs.filter { $0.st < next && $0.en > start }
}

/// До трёх цветных точек встреч дня (разные ящики — разные цвета).
private struct Dots: View {
  let evs: [CalEv]
  var body: some View {
    HStack(spacing: 2) {
      ForEach(Array(evs.prefix(3).enumerated()), id: \.offset) { _, e in
        Circle().fill(e.color).frame(width: 4, height: 4)
      }
    }
    .frame(height: 5)
  }
}

private func timeText(_ d: Date, _ lang: String) -> String {
  let f = DateFormatter()
  if !lang.isEmpty { f.locale = Locale(identifier: lang) }
  f.timeStyle = .short
  f.dateStyle = .none
  return f.string(from: d)
}

/// Обновление — в полночь (сменится «сегодня») или через 30 минут.
struct DayProvider: TimelineProvider {
  let key: String
  func placeholder(in context: Context) -> JSONEntry { JSONEntry(date: Date(), json: nil) }
  func getSnapshot(in context: Context, completion: @escaping (JSONEntry) -> Void) {
    completion(JSONEntry(date: Date(), json: loadJSON(key)))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<JSONEntry>) -> Void) {
    let now = Date()
    let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(24 * 3600))
    let next = min(midnight, now.addingTimeInterval(30 * 60))
    completion(Timeline(entries: [JSONEntry(date: now, json: loadJSON(key))], policy: .after(next)))
  }
}

struct CalendarWeekView: View {
  let entry: JSONEntry
  @Environment(\.widgetFamily) var family

  var body: some View {
    let j = entry.json ?? [:]
    let lang = j.str("lang")
    let cal = calendarFor(lang)
    let now = entry.date
    let evs = calEvents(j)
    let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
    let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    let wd = DateFormatter()
    let _ = { if !lang.isEmpty { wd.locale = Locale(identifier: lang) }; wd.setLocalizedDateFormatFromTemplate("EEEEEE") }()
    let rangeF = dateFormatter(lang)
    // Встречи с сегодняшнего дня до конца недели — по дням.
    let rest = days.filter { $0 >= cal.startOfDay(for: now) }
    let maxRows = family == .systemLarge ? 8 : 2
    VStack(alignment: .leading, spacing: 8) {
      Header(title: j.str("title").isEmpty ? "Calendar" : j.str("title"),
             sub: "\(rangeF.string(from: days.first ?? now)) – \(rangeF.string(from: days.last ?? now))",
             action: "event", actionIcon: "plus")
      HStack(spacing: 0) {
        ForEach(Array(days.enumerated()), id: \.offset) { _, d in
          let today = cal.isDate(d, inSameDayAs: now)
          VStack(spacing: 3) {
            Text(wd.string(from: d).capitalized).font(.system(size: 11)).foregroundColor(cSub)
            Text("\(cal.component(.day, from: d))")
              .font(.system(size: 14, weight: today ? .bold : .regular))
              .foregroundColor(today ? .white : cText)
              .frame(width: 26, height: 26)
              .background(Circle().fill(today ? cAccent : Color.clear))
            Dots(evs: events(evs, on: d, cal))
          }
          .frame(maxWidth: .infinity)
        }
      }
      if entry.json == nil {
        Text(NSLocalizedString("open_app", comment: "")).font(.system(size: 13)).foregroundColor(cSub)
      } else {
        let rows: [(Date, CalEv)] = rest.flatMap { d in events(evs, on: d, cal).map { (d, $0) } }
        if rows.isEmpty {
          Text(j.str("freeWeek").isEmpty ? j.str("free") : j.str("freeWeek"))
            .font(.system(size: 13)).foregroundColor(cSub)
        }
        ForEach(Array(rows.prefix(maxRows).enumerated()), id: \.offset) { i, r in
          let showDay = i == 0 || !cal.isDate(rows[i - 1].0, inSameDayAs: r.0)
          if showDay && family == .systemLarge {
            Text(dayLabel(r.0, j, rangeF).uppercased())
              .font(.system(size: 11, weight: .bold)).foregroundColor(cSub).padding(.top, i == 0 ? 0 : 2)
          }
          HStack(spacing: 8) {
            Text(r.1.allDay ? j.str("allDay") : timeText(r.1.st, lang))
              .font(.system(size: 13, weight: .semibold)).foregroundColor(cText).lineLimit(1)
              .frame(width: 52, alignment: .leading)
            RoundedRectangle(cornerRadius: 1.5).fill(r.1.color).frame(width: 3, height: 18)
            Text(r.1.title).font(.system(size: 14)).foregroundColor(cText).lineLimit(1)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .widgetURL(widgetURL("calendar"))
    .widgetBackground()
  }
}

struct CalendarWeekWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "OgnelissCalendarWeek", provider: DayProvider(key: "widget_calendar")) {
      CalendarWeekView(entry: $0)
    }
    .configurationDisplayName(NSLocalizedString("calweek_label", comment: ""))
    .description(NSLocalizedString("calweek_desc", comment: ""))
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}

// MARK: - Выбор дня в «Календарь: месяц» (1.7.0, iOS 17+)
//
// Как на Android: касание дня — его встречи под сеткой, стрелки — соседний
// месяц (от прошлого до третьего вперёд: столько встреч приложение кладёт
// виджету). Выбор хранится в App Group и через 6 часов сбрасывается на
// «сегодня» (как на Android). Кнопки внутри виджета iOS умеет с iOS 17
// (AppIntents); на iOS 15–16 виджет показывает текущий месяц и встречи
// сегодняшнего дня, касание открывает календарь приложения.

private let monthSelKey = "widget_month_sel"
private let monthAnchorKey = "widget_month_anchor"
private let monthAtKey = "widget_month_at"
private let monthStale: TimeInterval = 6 * 3600

/// Показанный месяц (его первое число) и выбранный день — сохранённые, если
/// не устарели.
private func monthState(now: Date) -> (anchor: Date, selected: Date) {
  let cal = Calendar.current
  let today = cal.startOfDay(for: now)
  let thisMonth = cal.dateInterval(of: .month, for: today)?.start ?? today
  let d = UserDefaults(suiteName: appGroup)
  let at = d?.double(forKey: monthAtKey) ?? 0
  guard at > 0, now.timeIntervalSince1970 - at < monthStale else { return (thisMonth, today) }
  let a = d?.double(forKey: monthAnchorKey) ?? 0
  let s = d?.double(forKey: monthSelKey) ?? 0
  var anchor = a > 0 ? Date(timeIntervalSince1970: a) : thisMonth
  // Не дальше данных: прошлый месяц … +2.
  if let lo = cal.date(byAdding: .month, value: -1, to: thisMonth),
     let hi = cal.date(byAdding: .month, value: 2, to: thisMonth) {
    anchor = min(max(anchor, lo), hi)
  }
  let sel = s > 0 ? Date(timeIntervalSince1970: s) : nil
  if let sel = sel, cal.isDate(sel, equalTo: anchor, toGranularity: .month) {
    return (anchor, cal.startOfDay(for: sel))
  }
  if cal.isDate(today, equalTo: anchor, toGranularity: .month) { return (anchor, today) }
  return (anchor, anchor)
}

private func saveMonthState(anchor: Date, selected: Date) {
  let d = UserDefaults(suiteName: appGroup)
  d?.set(anchor.timeIntervalSince1970, forKey: monthAnchorKey)
  d?.set(selected.timeIntervalSince1970, forKey: monthSelKey)
  d?.set(Date().timeIntervalSince1970, forKey: monthAtKey)
}

/// Касание дня в сетке месяца.
@available(iOS 17.0, *)
struct SelectMonthDayIntent: AppIntent {
  static let title: LocalizedStringResource = "Select day"
  static let isDiscoverable = false

  /// Начало дня, секунды с 1970 года.
  @Parameter(title: "Day") var day: Double

  init() {}
  init(day: Date) { self.day = day.timeIntervalSince1970 }

  func perform() async throws -> some IntentResult {
    let cal = Calendar.current
    let d = Date(timeIntervalSince1970: day)
    // День соседнего месяца (серые числа по краям сетки) — переход к нему.
    let anchor = cal.dateInterval(of: .month, for: d)?.start ?? d
    saveMonthState(anchor: anchor, selected: cal.startOfDay(for: d))
    return .result()
  }
}

/// Стрелки «‹ ›» — соседний месяц.
@available(iOS 17.0, *)
struct ShiftMonthIntent: AppIntent {
  static let title: LocalizedStringResource = "Change month"
  static let isDiscoverable = false

  @Parameter(title: "Months") var delta: Int

  init() {}
  init(delta: Int) { self.delta = delta }

  func perform() async throws -> some IntentResult {
    let cal = Calendar.current
    let now = Date()
    let current = monthState(now: now).anchor
    let next = cal.date(byAdding: .month, value: delta, to: current) ?? current
    let today = cal.startOfDay(for: now)
    // В текущем месяце — сегодня, в другом — первое число (как на Android).
    let sel = cal.isDate(today, equalTo: next, toGranularity: .month) ? today : next
    saveMonthState(anchor: next, selected: sel)
    return .result()
  }
}

/// Лента «Календарь: месяц»: как [DayProvider] и выбранный день с месяцем.
struct MonthProvider: TimelineProvider {
  let key: String
  func placeholder(in context: Context) -> JSONEntry { JSONEntry(date: Date(), json: nil) }
  func getSnapshot(in context: Context, completion: @escaping (JSONEntry) -> Void) {
    completion(entry(Date()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<JSONEntry>) -> Void) {
    let now = Date()
    let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(24 * 3600))
    let next = min(midnight, now.addingTimeInterval(30 * 60))
    completion(Timeline(entries: [entry(now)], policy: .after(next)))
  }
  private func entry(_ now: Date) -> JSONEntry {
    var e = JSONEntry(date: now, json: loadJSON(key))
    if #available(iOSApplicationExtension 17.0, *) {
      let st = monthState(now: now)
      e.anchor = st.anchor
      e.selected = st.selected
    }
    return e
  }
}

/// День сетки: на iOS 17 — кнопка выбора дня, раньше — просто число.
private struct DayCell<Content: View>: View {
  let day: Date
  @ViewBuilder let content: () -> Content
  var body: some View {
    if #available(iOSApplicationExtension 17.0, *) {
      Button(intent: SelectMonthDayIntent(day: day)) { content() }.buttonStyle(.plain)
    } else {
      content()
    }
  }
}

/// Заголовок месяца: на iOS 17 — со стрелками «‹ ›», раньше — обычный.
private struct MonthHeader: View {
  let title: String
  let sub: String
  let interactive: Bool
  let canBack: Bool
  let canFwd: Bool

  var body: some View {
    if #available(iOSApplicationExtension 17.0, *) {
      if interactive {
        HStack(spacing: 4) {
          Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(cAccent).lineLimit(1)
          Spacer(minLength: 4)
          arrow(-1, "chevron.left", canBack)
          arrow(1, "chevron.right", canFwd)
          Link(destination: widgetURL("event")) {
            Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).foregroundColor(cAccent)
              .frame(width: 28, height: 28)
          }
        }
      } else {
        Header(title: title, sub: sub, action: "event", actionIcon: "plus")
      }
    } else {
      Header(title: title, sub: sub, action: "event", actionIcon: "plus")
    }
  }

  @available(iOSApplicationExtension 17.0, *)
  private func arrow(_ delta: Int, _ icon: String, _ enabled: Bool) -> some View {
    Button(intent: ShiftMonthIntent(delta: delta)) {
      Image(systemName: icon).font(.system(size: 15, weight: .semibold))
        .foregroundColor(enabled ? cAccent : cSub.opacity(0.35)).frame(width: 30, height: 28)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }
}

/// «Календарь: месяц» (1.6.49+95, как на Android): сетка месяца строками
/// постоянной высоты, сегодня — кружком акцента, под сеткой — встречи
/// выбранного дня. С 1.7.0 на iOS 17 и новее день выбирается касанием, а
/// месяц — стрелками; на iOS 15–16 — сегодняшний день, касание открывает
/// календарь приложения.
struct CalendarMonthView: View {
  let entry: JSONEntry

  var body: some View {
    let j = entry.json ?? [:]
    let lang = j.str("lang")
    let cal = calendarFor(lang)
    let now = entry.date
    let evs = calEvents(j)
    let shown = entry.anchor ?? now
    let selDay = entry.selected ?? cal.startOfDay(for: now)
    let interactive = entry.anchor != nil
    let monthStart = cal.dateInterval(of: .month, for: shown)?.start ?? cal.startOfDay(for: shown)
    let gridStart = cal.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart
    let month = cal.component(.month, from: shown)
    let daysInView: [Date] = (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    // 5 или 6 недель — сколько занимает месяц.
    let weeks = daysInView.count >= 42 && cal.component(.month, from: daysInView[35]) != month ? 5 : 6
    let mf = DateFormatter()
    let wd = DateFormatter()
    let _ = {
      if !lang.isEmpty { mf.locale = Locale(identifier: lang); wd.locale = Locale(identifier: lang) }
      mf.setLocalizedDateFormatFromTemplate("LLLLyyyy")
      wd.setLocalizedDateFormatFromTemplate("EEEEEE")
    }()
    let dayEvents = events(evs, on: selDay, cal)
    let rangeF = dateFormatter(lang)
    let thisMonth = cal.dateInterval(of: .month, for: now)?.start ?? now
    let canBack = interactive && monthStart > (cal.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth)
    let canFwd = interactive && monthStart < (cal.date(byAdding: .month, value: 2, to: thisMonth) ?? thisMonth)
    VStack(alignment: .leading, spacing: 4) {
      MonthHeader(title: mf.string(from: shown).capitalized, sub: j.str("title"),
                  interactive: interactive, canBack: canBack, canFwd: canFwd)
      HStack(spacing: 0) {
        ForEach(0..<7, id: \.self) { i in
          Text(wd.string(from: daysInView[i]).capitalized)
            .font(.system(size: 11)).foregroundColor(cSub).frame(maxWidth: .infinity)
        }
      }
      VStack(spacing: 1) {
        ForEach(0..<weeks, id: \.self) { w in
          HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
              let d = daysInView[w * 7 + i]
              let today = cal.isDate(d, inSameDayAs: now)
              let picked = interactive && !today && cal.isDate(d, inSameDayAs: selDay)
              let inMonth = cal.component(.month, from: d) == month
              DayCell(day: d) {
                VStack(spacing: 1) {
                  Text("\(cal.component(.day, from: d))")
                    .font(.system(size: 13, weight: today || picked ? .bold : .regular))
                    .foregroundColor(today ? .white : (picked ? cAccent : (inMonth ? cText : cSub.opacity(0.6))))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(today ? cAccent : Color.clear))
                    // Выбранный день — кольцом (сегодня — заливкой).
                    .overlay(Circle().stroke(picked ? cAccent : Color.clear, lineWidth: 1.5))
                  Dots(evs: events(evs, on: d, cal))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
              }
              .frame(maxWidth: .infinity)
            }
          }
          .frame(height: 28)
        }
      }
      if entry.json == nil {
        Text(NSLocalizedString("open_app", comment: "")).font(.system(size: 13)).foregroundColor(cSub)
      } else {
        // Встречи выбранного дня (без выбора — сегодняшнего) — под сеткой.
        Text(dayLabel(selDay, j, rangeF).uppercased())
          .font(.system(size: 11, weight: .bold)).foregroundColor(cSub).padding(.top, 4)
        if dayEvents.isEmpty {
          Text(j.str("free")).font(.system(size: 13)).foregroundColor(cSub)
        }
        ForEach(Array(dayEvents.prefix(weeks == 6 ? 3 : 4).enumerated()), id: \.offset) { _, e in
          HStack(spacing: 8) {
            Text(e.allDay ? j.str("allDay") : timeText(e.st, lang))
              .font(.system(size: 13, weight: .semibold)).foregroundColor(cText).lineLimit(1)
              .frame(width: 52, alignment: .leading)
            RoundedRectangle(cornerRadius: 1.5).fill(e.color).frame(width: 3, height: 16)
            Text(e.title).font(.system(size: 14)).foregroundColor(cText).lineLimit(1)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .widgetURL(widgetURL("calendar"))
    .widgetBackground()
  }
}

struct CalendarMonthWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "OgnelissCalendarMonth", provider: MonthProvider(key: "widget_calendar")) {
      CalendarMonthView(entry: $0)
    }
    .configurationDisplayName(NSLocalizedString("calmonth_label", comment: ""))
    .description(NSLocalizedString("calmonth_desc", comment: ""))
    .supportedFamilies([.systemLarge])
  }
}

// MARK: - Набор

@main
struct OgnelissWidgets: WidgetBundle {
  var body: some Widget {
    MyDayWidget()
    MailWidget()
    CalendarWidget()
    CalendarWeekWidget()
    CalendarMonthWidget()
    NotesWidget()
  }
}
