import Contacts
import EventKit
import Flutter
import Foundation

// iOS-реализация MethodChannel('ogneliss/phone_mirror') — зеркало
// PhoneMirrorPlugin.kt (Dart: lib/services/device/phone_mirror_service.dart).
//
// Контакты ящика — отдельная группа «Ogneliss — ящик» в «Контактах»;
// встречи — отдельный календарь «Ogneliss — ящик». Направление — из
// приложения в телефон. Соответствие «id в приложении → запись в телефоне»
// и хэш полей хранятся в UserDefaults: неизменённые записи не переписываются,
// удалённые в приложении — удаляются.
//
// Разрешения запрашивает Dart (permission_handler): Permission.contacts и
// Permission.calendarFullAccess. Без них — ошибка NO_PERMISSION.

enum PhoneMirrorPlugin {
    private static let queue = DispatchQueue(label: "ogneliss.phone_mirror")
    private static let defaults = UserDefaults.standard

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "ogneliss/phone_mirror", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            if call.method == "ping" { result(true); return }
            let args = call.arguments as? [String: Any] ?? [:]
            queue.async {
                do {
                    let value: Any
                    switch call.method {
                    case "syncContacts": value = try syncContacts(args)
                    case "syncEvents": value = try syncEvents(args)
                    case "remove": try remove(args); value = true
                    case "prune": value = prune(args)
                    default:
                        DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
                        return
                    }
                    DispatchQueue.main.async { result(value) }
                } catch MirrorError.noPermission {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "NO_PERMISSION", message: "access denied", details: nil))
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "FAILED", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }

    enum MirrorError: Error { case noPermission }

    // MARK: - Соответствие id → (идентификатор в телефоне, хэш)

    private static func loadMap(_ key: String) -> [String: [String]] {
        defaults.dictionary(forKey: key) as? [String: [String]] ?? [:]
    }

    private static func saveMap(_ key: String, _ map: [String: [String]]) {
        defaults.set(map, forKey: key)
    }

    private static func contactsKey(_ account: String) -> String { "phoneMirror.contacts.\(account)" }
    private static func eventsKey(_ account: String) -> String { "phoneMirror.events.\(account)" }
    private static func groupKey(_ account: String) -> String { "phoneMirror.group.\(account)" }
    private static func calendarKey(_ account: String) -> String { "phoneMirror.calendar.\(account)" }
    private static let accountsKey = "phoneMirror.accounts"

    private static func rememberAccount(_ account: String) {
        var list = defaults.stringArray(forKey: accountsKey) ?? []
        if !list.contains(account) { list.append(account); defaults.set(list, forKey: accountsKey) }
    }

    // MARK: - Контакты

    private static let keys: [CNKeyDescriptor] = [
        CNContactGivenNameKey, CNContactFamilyNameKey, CNContactMiddleNameKey,
        CNContactOrganizationNameKey, CNContactDepartmentNameKey, CNContactJobTitleKey,
        CNContactEmailAddressesKey, CNContactPhoneNumbersKey,
    ] as [CNKeyDescriptor]

    private static func fill(_ c: CNMutableContact, _ m: [String: Any]) {
        func s(_ k: String) -> String { (m[k] as? String)?.trimmingCharacters(in: .whitespaces) ?? "" }
        c.givenName = s("givenName").isEmpty && s("familyName").isEmpty ? s("displayName") : s("givenName")
        c.familyName = s("familyName")
        c.middleName = s("middleName")
        c.organizationName = s("company")
        c.departmentName = s("department")
        c.jobTitle = s("jobTitle")
        let emails = (m["emails"] as? [String] ?? []).filter { !$0.isEmpty }
        c.emailAddresses = emails.map { CNLabeledValue(label: CNLabelWork, value: $0 as NSString) }
        var phones: [CNLabeledValue<CNPhoneNumber>] = []
        if !s("phoneMobile").isEmpty {
            phones.append(CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: s("phoneMobile"))))
        }
        if !s("phoneWork").isEmpty {
            phones.append(CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: s("phoneWork"))))
        }
        c.phoneNumbers = phones
    }

    private static func ensureGroup(_ store: CNContactStore, account: String, title: String) throws -> CNGroup {
        if let id = defaults.string(forKey: groupKey(account)),
           let g = try? store.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [id])).first {
            return g
        }
        let g = CNMutableGroup()
        g.name = title
        let req = CNSaveRequest()
        req.add(g, toContainerWithIdentifier: nil)
        try store.execute(req)
        defaults.set(g.identifier, forKey: groupKey(account))
        return g
    }

    private static func syncContacts(_ args: [String: Any]) throws -> Int {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { throw MirrorError.noPermission }
        guard let account = args["account"] as? String else { return 0 }
        let title = args["groupName"] as? String ?? "Ogneliss — \(account)"
        let items = args["contacts"] as? [[String: Any]] ?? []
        let store = CNContactStore()
        let group = try ensureGroup(store, account: account, title: title)
        rememberAccount(account)
        var map = loadMap(contactsKey(account))
        var seen = Set<String>()
        var written = 0
        for m in items {
            guard let id = m["id"] as? String else { continue }
            let hash = m["hash"] as? String ?? ""
            seen.insert(id)
            if let old = map[id], old.count == 2, old[1] == hash { continue }
            let req = CNSaveRequest()
            if let old = map[id], let existing = try? store.unifiedContact(withIdentifier: old[0], keysToFetch: keys),
               let mutable = existing.mutableCopy() as? CNMutableContact {
                fill(mutable, m)
                req.update(mutable)
                try store.execute(req)
                map[id] = [mutable.identifier, hash]
            } else {
                let c = CNMutableContact()
                fill(c, m)
                req.add(c, toContainerWithIdentifier: nil)
                req.addMember(c, to: group)
                try store.execute(req)
                map[id] = [c.identifier, hash]
            }
            written += 1
        }
        // Удалённые в приложении — удалить и из телефона.
        for (id, v) in map where !seen.contains(id) {
            if let c = try? store.unifiedContact(withIdentifier: v[0], keysToFetch: keys),
               let mutable = c.mutableCopy() as? CNMutableContact {
                let req = CNSaveRequest()
                req.delete(mutable)
                try? store.execute(req)
            }
            map.removeValue(forKey: id)
        }
        saveMap(contactsKey(account), map)
        return written
    }

    private static func removeContacts(_ account: String) {
        let store = CNContactStore()
        for (_, v) in loadMap(contactsKey(account)) {
            if let c = try? store.unifiedContact(withIdentifier: v[0], keysToFetch: keys),
               let mutable = c.mutableCopy() as? CNMutableContact {
                let req = CNSaveRequest()
                req.delete(mutable)
                try? store.execute(req)
            }
        }
        if let id = defaults.string(forKey: groupKey(account)),
           let g = try? store.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [id])).first,
           let mg = g.mutableCopy() as? CNMutableGroup {
            let req = CNSaveRequest()
            req.delete(mg)
            try? store.execute(req)
        }
        defaults.removeObject(forKey: contactsKey(account))
        defaults.removeObject(forKey: groupKey(account))
    }

    // MARK: - Календарь

    private static func calendarAuthorized() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) { return status == .fullAccess }
        return status == .authorized
    }

    private static func ensureCalendar(_ store: EKEventStore, account: String, title: String, color: Int) throws -> EKCalendar {
        if let id = defaults.string(forKey: calendarKey(account)), let cal = store.calendar(withIdentifier: id) {
            cal.title = title
            cal.cgColor = cgColor(color)
            try? store.saveCalendar(cal, commit: true)
            return cal
        }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = title
        cal.cgColor = cgColor(color)
        // Источник: «На iPhone», если есть; иначе — тот же, что у календаря по умолчанию.
        cal.source = store.sources.first(where: { $0.sourceType == .local })
            ?? store.defaultCalendarForNewEvents?.source
            ?? store.sources.first
        try store.saveCalendar(cal, commit: true)
        defaults.set(cal.calendarIdentifier, forKey: calendarKey(account))
        return cal
    }

    private static func cgColor(_ argb: Int) -> CGColor {
        let r = CGFloat((argb >> 16) & 0xFF) / 255, g = CGFloat((argb >> 8) & 0xFF) / 255, b = CGFloat(argb & 0xFF) / 255
        return CGColor(red: r, green: g, blue: b, alpha: 1)
    }

    private static func syncEvents(_ args: [String: Any]) throws -> Int {
        guard calendarAuthorized() else { throw MirrorError.noPermission }
        guard let account = args["account"] as? String else { return 0 }
        let title = args["calendarName"] as? String ?? "Ogneliss — \(account)"
        let color = (args["color"] as? NSNumber)?.intValue ?? 0x1D4F91
        let items = args["events"] as? [[String: Any]] ?? []
        let store = EKEventStore()
        let cal = try ensureCalendar(store, account: account, title: title, color: color)
        rememberAccount(account)
        var map = loadMap(eventsKey(account))
        var seen = Set<String>()
        var written = 0
        for m in items {
            guard let id = m["id"] as? String,
                  let start = (m["start"] as? NSNumber)?.doubleValue,
                  let end = (m["end"] as? NSNumber)?.doubleValue else { continue }
            let hash = m["hash"] as? String ?? ""
            seen.insert(id)
            if let old = map[id], old.count == 2, old[1] == hash { continue }
            let ev: EKEvent
            if let old = map[id], let existing = store.event(withIdentifier: old[0]) {
                ev = existing
            } else {
                ev = EKEvent(eventStore: store)
                ev.calendar = cal
            }
            ev.title = m["title"] as? String ?? ""
            ev.notes = m["description"] as? String
            ev.location = m["location"] as? String
            let allDay = m["allDay"] as? Bool ?? false
            ev.isAllDay = allDay
            if allDay {
                // Dart передаёт полночь UTC — для iOS это даты в текущем поясе.
                var utc = Calendar(identifier: .gregorian)
                utc.timeZone = TimeZone(identifier: "UTC")!
                let s = utc.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: start / 1000))
                let e = utc.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: end / 1000))
                ev.startDate = Calendar.current.date(from: s) ?? Date(timeIntervalSince1970: start / 1000)
                ev.endDate = Calendar.current.date(from: e) ?? Date(timeIntervalSince1970: end / 1000)
            } else {
                ev.startDate = Date(timeIntervalSince1970: start / 1000)
                ev.endDate = Date(timeIntervalSince1970: end / 1000)
            }
            ev.alarms = nil
            if let minutes = (m["reminderMinutes"] as? NSNumber)?.doubleValue {
                ev.addAlarm(EKAlarm(relativeOffset: -minutes * 60))
            }
            try store.save(ev, span: .thisEvent, commit: false)
            map[id] = [ev.eventIdentifier ?? "", hash]
            written += 1
        }
        for (id, v) in map where !seen.contains(id) {
            if let ev = store.event(withIdentifier: v[0]) {
                try? store.remove(ev, span: .thisEvent, commit: false)
            }
            map.removeValue(forKey: id)
        }
        try store.commit()
        saveMap(eventsKey(account), map)
        return written
    }

    private static func removeCalendar(_ account: String) {
        let store = EKEventStore()
        if let id = defaults.string(forKey: calendarKey(account)), let cal = store.calendar(withIdentifier: id) {
            try? store.removeCalendar(cal, commit: true)
        }
        defaults.removeObject(forKey: calendarKey(account))
        defaults.removeObject(forKey: eventsKey(account))
    }

    // MARK: - Удаление

    private static func remove(_ args: [String: Any]) throws {
        guard let account = args["account"] as? String else { return }
        let all = args["removeAccount"] as? Bool ?? false
        if all || (args["contacts"] as? Bool ?? false) { removeContacts(account) }
        if all || (args["calendar"] as? Bool ?? false) { removeCalendar(account) }
    }

    private static func prune(_ args: [String: Any]) -> Int {
        guard let keep = args["keep"] as? [String] else { return 0 }
        var list = defaults.stringArray(forKey: accountsKey) ?? []
        var n = 0
        for account in list where !keep.contains(account) {
            removeContacts(account)
            removeCalendar(account)
            n += 1
        }
        list = list.filter { keep.contains($0) }
        defaults.set(list, forKey: accountsKey)
        return n
    }
}
