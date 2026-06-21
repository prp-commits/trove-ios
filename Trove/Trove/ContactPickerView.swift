import SwiftUI
import ContactsUI
import Contacts

/// A one-time system contact picker (Phase C, slice 5), shown when Trove hasn't yet
/// learned which contact a person maps to. `CNContactPickerViewController` runs
/// out-of-process, so it needs **no Contacts permission** — the user's pick is
/// returned without Trove ever reading the address book. We keep only the chosen
/// contact's name + one phone number, on-device (see `ContactLinkStore`).
struct ContactPickerView: UIViewControllerRepresentable {
    var onPick: @MainActor (ContactLink) -> Void
    var onCancel: @MainActor () -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPickerView
        init(_ parent: ContactPickerView) { self.parent = parent }

        // CNContactPickerDelegate calls these on the main thread.
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            MainActor.assumeIsolated { parent.onCancel() }
        }

        // A whole contact was chosen.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            MainActor.assumeIsolated {
                guard let phone = ContactLinkStore.bestPhone(contact) else { parent.onCancel(); return }
                parent.onPick(ContactLink(name: displayName(contact), phone: phone))
            }
        }

        // A specific phone number was chosen (user drilled into a multi-number card).
        func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
            MainActor.assumeIsolated {
                guard property.key == CNContactPhoneNumbersKey,
                      let number = (property.value as? CNPhoneNumber)?.stringValue else {
                    parent.onCancel(); return
                }
                parent.onPick(ContactLink(name: displayName(property.contact), phone: number))
            }
        }

        private func displayName(_ c: CNContact) -> String {
            [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
}
