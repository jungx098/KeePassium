//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

protocol HardwareKeyPickerDelegate: class {
    func didPressCancel(in picker: HardwareKeyPicker)
    func didSelectKey(yubiKey: YubiKey?, in picker: HardwareKeyPicker)
}

class HardwareKeyPicker: UITableViewController, Refreshable {
    weak var delegate: HardwareKeyPickerDelegate?
    
    public var key: YubiKey? {
        didSet { refresh() }
    }
    
    /// A convenience delegate to present this VC in a dismissable popover.
    public let dismissablePopoverDelegate = DismissablePopover(leftButton: .cancel, rightButton: nil)
    
    private let nfcKeys: [YubiKey] = [
        YubiKey(interface: .nfc, slot: .slot1),
        YubiKey(interface: .nfc, slot: .slot2)]
    private let mfiKeys: [YubiKey] = [
        YubiKey(interface: .mfi, slot: .slot1),
        YubiKey(interface: .mfi, slot: .slot2)]

    private enum Section: Int {
        static let allValues = [.noHardwareKey, yubiKeyNFC, yubiKeyMFI]
        case noHardwareKey
        case yubiKeyNFC
        case yubiKeyMFI
        var title: String? {
            switch self {
            case .noHardwareKey:
                return nil
            case .yubiKeyNFC:
                return "NFC"
            case .yubiKeyMFI:
                return "Lightning"
            }
        }
    }
    private var isChoiceMade = false
    
    // MARK: - VC lifecycle
    
    public static func create(delegate: HardwareKeyPickerDelegate?=nil) -> HardwareKeyPicker {
        let vc = HardwareKeyPicker.instantiateFromStoryboard()
        vc.delegate = delegate
        return vc
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if !isChoiceMade {
            delegate?.didPressCancel(in: self)
        }
    }
    
    func refresh() {
        tableView.reloadData()
    }
    
    // MARK: - UITableViewDataSourceDelegate
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allValues.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            assertionFailure()
            return 0
        }
        switch section {
        case .noHardwareKey:
            return 1
        case .yubiKeyNFC:
            return nfcKeys.count
        case .yubiKeyMFI:
            return mfiKeys.count
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else {
            assertionFailure()
            return nil
        }
        return section.title
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            fatalError()
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)

        let key: YubiKey?
        switch section {
        case .noHardwareKey:
            key = nil
        case .yubiKeyNFC:
            key = nfcKeys[indexPath.row]
        case .yubiKeyMFI:
            key = mfiKeys[indexPath.row]
        }
        cell.textLabel?.text = getKeyDescription(key)
        cell.accessoryType = (key == self.key) ? .checkmark : .none
        return cell
    }
    
    private func getKeyDescription(_ key: YubiKey?) -> String {
        guard let key = key else {
            return NSLocalizedString(
                "[HardwareKey/None] No Hardware Key",
                value: "No Hardware Key",
                comment: "Master key/unlock option: don't use hardware keys")
        }
        
        let template = NSLocalizedString(
            "[HardwareKey/YubiKey/Slot] YubiKey Slot #%d",
            value: "YubiKey Slot %d",
            comment: "Master key/unlock option: use given slot of YubiKey")
        let result = String.localizedStringWithFormat(template, key.slot.number)
        return result
    }
    
    // MARK: - Actions
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = Section(rawValue: indexPath.section) else {
            assertionFailure()
            return
        }
        
        let selectedKey: YubiKey?
        switch section {
        case .noHardwareKey:
            selectedKey = nil
        case .yubiKeyNFC:
            selectedKey = nfcKeys[indexPath.row]
        case .yubiKeyMFI:
            selectedKey = mfiKeys[indexPath.row]
        }
        isChoiceMade = true
        delegate?.didSelectKey(yubiKey: selectedKey, in: self)
        dismiss(animated: true, completion: nil)
    }
}

extension HardwareKeyPicker: UIPopoverPresentationControllerDelegate {

    func presentationController(
        _ controller: UIPresentationController,
        viewControllerForAdaptivePresentationStyle style: UIModalPresentationStyle
        ) -> UIViewController?
    {
        if style != .popover {
            let navVC = controller.presentedViewController as? UINavigationController
            let cancelButton = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(dismissPopover))
            navVC?.topViewController?.navigationItem.leftBarButtonItem = cancelButton
        }
        return nil // "keep existing"
    }
    
    @objc func dismissPopover() {
        dismiss(animated: true, completion: nil)
    }
}
