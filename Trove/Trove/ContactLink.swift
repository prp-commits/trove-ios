import Foundation
import Contacts

/// On-device link between a Trove entity and a phone number from the user's
/// contacts (Phase C, slice 5). It lets a Review nudge pre-address the Messages
/// composer for the right person. **Everything here stays on the device** — the
/// phone number and the entity↔contact link live only in local UserDefaults and are
/// never sent to the server. Cleared on sign-out.
struct ContactLink: Codable, Sendable {
    let name: String     // contact display name (what the composer shows)
    let phone: String
}

@MainActor
enum ContactLinkStore {
    private static let key = "entityContactLinks"   // ["\(entityId)": ContactLink]

    private static func all() -> [String: ContactLink] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let map = try? JSONDecoder().decode([String: ContactLink].self, from: data)
        else { return [:] }
        return map
    }

    private static func persist(_ map: [String: ContactLink]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func link(for entityId: Int) -> ContactLink? { all()["\(entityId)"] }

    static func save(_ link: ContactLink, for entityId: Int) {
        var map = all(); map["\(entityId)"] = link; persist(map)
    }

    /// Forget every learned link + number (sign-out / privacy reset).
    static func forget() { UserDefaults.standard.removeObject(forKey: key) }

    /// Resolve a number to pre-address the composer:
    /// 1. a previously stored link (including one the user picked), else
    /// 2. a *confident* auto-match against device contacts (exact, unique name with a
    ///    phone) — only when Contacts access is already granted.
    /// Returns nil when the caller should fall back to the one-time contact picker.
    static func resolve(entityId: Int, name: String) -> ContactLink? {
        if let existing = link(for: entityId) { return existing }
        guard ContactsReader.shared.isAuthorized else { return nil }
        guard let matched = autoMatch(name: name) else { return nil }
        save(matched, for: entityId)
        return matched
    }

    /// Exactly one contact whose full name (or, for a single-token entity name, given
    /// name) matches case/diacritic-insensitively AND has a phone number. Any
    /// ambiguity → nil: texting the wrong person is worse than one extra tap.
    private static func autoMatch(name: String) -> ContactLink? {
        let target = normalize(name)
        guard !target.isEmpty else { return nil }
        let singleToken = !target.contains(" ")

        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey,
                    CNContactPhoneNumbersKey].map { $0 as CNKeyDescriptor }
        var matches: [ContactLink] = []
        do {
            try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, stop in
                let full = normalize([c.givenName, c.familyName]
                    .filter { !$0.isEmpty }.joined(separator: " "))
                let given = normalize(c.givenName)
                let hit = full == target || (singleToken && given == target)
                guard hit, let phone = bestPhone(c) else { return }
                let display = [c.givenName, c.familyName]
                    .filter { !$0.isEmpty }.joined(separator: " ")
                matches.append(ContactLink(name: display, phone: phone))
                if matches.count > 1 { stop.pointee = true }   // ambiguous → bail
            }
        } catch { return nil }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Prefer an iPhone/mobile number, else the first one.
    static func bestPhone(_ c: CNContact) -> String? {
        let numbers = c.phoneNumbers
        guard !numbers.isEmpty else { return nil }
        let preferred = numbers.first { entry in
            let label = entry.label ?? ""
            return label == CNLabelPhoneNumberiPhone || label == CNLabelPhoneNumberMobile
        }
        return (preferred ?? numbers.first)?.value.stringValue
    }
}
