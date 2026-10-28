import Foundation
import EventKit
import Flutter

// iOS-реализация MethodChannel('ogneliss/device_calendar') — зеркало
// DeviceCalendarPlugin.kt. Контракт (lib/services/device/device_calendar_sync.dart):
//   ping     -> Bool
//   addEvent {title, startTime(ms), endTime(ms), description?, location?,
//             allDay?, reminderMinutes?} -> Bool
//
// NSCalendarsUsageDescription объявлен в Info.plist. Разрешение — на стороне Dart
// (permission_handler → EKEventStore). На iOS 17+ requestFullAccessToEvents.
//
// Регистрация: DeviceCalendarPlugin.register(with: controller.binaryMessenger)

enum DeviceCalendarPlugin {
    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "ogneliss/device_calendar", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "ping":
                result(true)
            case "addEvent":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "BAD_ARGS", message: "expected map", details: nil)); return
                }
                addEvent(args, result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private static func addEvent(_ m: [String: Any], result: @escaping FlutterResult) {
        let store = EKEventStore()

        let write: (Bool, Error?) -> Void = { granted, error in
            guard granted, error == nil else {
                result(FlutterError(code: "NO_ACCESS", message: error?.localizedDescription ?? "denied", details: nil))
                return
            }
            guard let startMs = m["startTime"] as? NSNumber, let endMs = m["endTime"] as? NSNumber else {
                result(FlutterError(code: "BAD_ARGS", message: "startTime/endTime required", details: nil)); return
            }
            let event = EKEvent(eventStore: store)
            event.title = (m["title"] as? String) ?? ""
            event.startDate = Date(timeIntervalSince1970: startMs.doubleValue / 1000.0)
            event.endDate = Date(timeIntervalSince1970: endMs.doubleValue / 1000.0)
            if let notes = m["description"] as? String { event.notes = notes }
            if let loc = m["location"] as? String { event.location = loc }
            if let allDay = m["allDay"] as? Bool { event.isAllDay = allDay }
            event.calendar = store.defaultCalendarForNewEvents
            if let minutes = m["reminderMinutes"] as? NSNumber {
                event.addAlarm(EKAlarm(relativeOffset: -(minutes.doubleValue * 60.0)))
            }
            do {
                try store.save(event, span: .thisEvent)
                result(true)
            } catch {
                result(FlutterError(code: "WRITE_FAILED", message: error.localizedDescription, details: nil))
            }
        }

        if #available(iOS 17.0, *) {
            store.requestFullAccessToEvents { granted, error in
                DispatchQueue.main.async { write(granted, error) }
            }
        } else {
            store.requestAccess(to: .event) { granted, error in
                DispatchQueue.main.async { write(granted, error) }
            }
        }
    }
}
