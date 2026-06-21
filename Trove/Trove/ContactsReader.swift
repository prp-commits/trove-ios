import Foundation
import Contacts

/// Reads the device's Contacts (Phase C, slice 3) into the normalized shape the
/// backend uses as a resolution dictionary (email → name) and a birthday source.
/// We only keep contacts that can actually help Trove — those with an email
/// (attendee resolution) or a birthday (nudges) — and only their name, emails, and
/// birthday. Nothing else leaves the device; the dictionary never creates a card.
@MainActor
final class ContactsReader {
    static let shared = ContactsReader()
    private let store = CNContactStore()

    var isAuthorized: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if #available(iOS 18.0, *) { return status == .authorized || status == .limited }
        return status == .authorized
    }

    func requestAccess() async -> Bool {
        await withCheckedContinuation { cont in
            store.requestAccess(for: .contacts) { granted, _ in cont.resume(returning: granted) }
        }
    }

    func collectContacts() -> [DeviceContact] {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactEmailAddressesKey, CNContactBirthdayKey,
        ].map { $0 as CNKeyDescriptor }

        var out: [DeviceContact] = []
        do {
            try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, _ in
                let name = [c.givenName, c.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                let emails = c.emailAddresses
                    .map { ($0.value as String).trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { $0.contains("@") }
                var birthday: DeviceBirthday?
                if let b = c.birthday, let m = b.month, let d = b.day {
                    birthday = DeviceBirthday(month: m, day: d, year: b.year)
                }
                // Keep only contacts that can help: a name plus an email or a birthday.
                guard !name.isEmpty, (!emails.isEmpty || birthday != nil) else { return }
                out.append(DeviceContact(name: name, emails: emails, birthday: birthday))
            }
        } catch {
            // Best-effort — a read failure just means we sync events without the dict.
        }
        return out
    }
}
