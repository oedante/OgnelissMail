import Foundation
import Contacts
import Flutter

// iOS-реализация MethodChannel('ogneliss/device_contacts') — зеркало
// DeviceContactsPlugin.kt. Контракт совпадает с Dart
// (lib/services/device/device_contacts_sync.dart):
//   ping        -> Bool
//   getContacts -> [[String: Any]] (email, displayName, givenName, familyName,
//                  middleName, phoneWork, phoneMobile, company, department, jobTitle)
//   addContact  {displayName, givenName, familyName, email, phoneWork,
//                phoneMobile, company, jobTitle, department} -> Bool
//
// Разрешение запрашивается на стороне Dart (permission_handler → CNContactStore).
// NSContactsUsageDescription объявлен в Info.plist.
//
// Регистрация в AppDelegate:
//   DeviceContactsPlugin.register(with: controller.binaryMessenger)

enum DeviceContactsPlugin {
    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "ogneliss/device_contacts", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "ping":
                result(true)
            case "getContacts":
                // Перебор адресной книги — не на главном потоке (большая книга
                // подвешивала бы интерфейс); ответ — на главном.
                DispatchQueue.global(qos: .userInitiated).async {
                    getContacts { value in DispatchQueue.main.async { result(value) } }
                }
            case "addContact":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "BAD_ARGS", message: "expected map", details: nil)); return
                }
                addContact(args, result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private static func getContacts(result: @escaping FlutterResult) {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]
        var out: [[String: Any]] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        do {
            try store.enumerateContacts(with: request) { c, _ in
                let email = c.emailAddresses.first?.value as String? ?? ""
                if email.isEmpty { return }
                var phoneWork: String?
                var phoneMobile: String?
                for p in c.phoneNumbers {
                    let label = p.label ?? ""
                    if label.contains("Work") || label.contains("work") {
                        phoneWork = p.value.stringValue
                    } else if label.contains("Mobile") || label.contains("mobile") || label.contains("iPhone") {
                        phoneMobile = p.value.stringValue
                    } else if phoneMobile == nil {
                        phoneMobile = p.value.stringValue
                    }
                }
                let displayName = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                out.append([
                    "email": email,
                    "displayName": displayName.isEmpty ? email : displayName,
                    "givenName": c.givenName,
                    "familyName": c.familyName,
                    "middleName": c.middleName,
                    "phoneWork": phoneWork as Any,
                    "phoneMobile": phoneMobile as Any,
                    "company": c.organizationName,
                    "department": c.departmentName,
                    "jobTitle": c.jobTitle,
                ])
            }
            result(out)
        } catch {
            result(FlutterError(code: "READ_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private static func addContact(_ m: [String: Any], result: @escaping FlutterResult) {
        let contact = CNMutableContact()
        contact.givenName = (m["givenName"] as? String) ?? ""
        contact.familyName = (m["familyName"] as? String) ?? ""
        if let org = m["company"] as? String { contact.organizationName = org }
        if let title = m["jobTitle"] as? String { contact.jobTitle = title }
        if let dept = m["department"] as? String { contact.departmentName = dept }
        if let email = m["email"] as? String, !email.isEmpty {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)]
        }
        var phones: [CNLabeledValue<CNPhoneNumber>] = []
        if let pw = m["phoneWork"] as? String, !pw.isEmpty {
            phones.append(CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: pw)))
        }
        if let pm = m["phoneMobile"] as? String, !pm.isEmpty {
            phones.append(CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: pm)))
        }
        contact.phoneNumbers = phones

        let store = CNContactStore()
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        do {
            try store.execute(request)
            result(true)
        } catch {
            result(FlutterError(code: "WRITE_FAILED", message: error.localizedDescription, details: nil))
        }
    }
}
