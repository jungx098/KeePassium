//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit
import KeePassiumLib

class ChangeMasterKeyVC: UIViewController {
    @IBOutlet weak var keyboardAdjView: UIView!
    @IBOutlet weak var databaseNameLabel: UILabel!
    @IBOutlet weak var databaseIcon: UIImageView!
    @IBOutlet weak var passwordField: ValidatingTextField!
    @IBOutlet weak var repeatPasswordField: ValidatingTextField!
    @IBOutlet weak var keyFileField: KeyFileTextField!
    @IBOutlet weak var passwordMismatchImage: UIImageView!
    
    private var databaseRef: URLReference!
    private var keyFileRef: URLReference?
    private var yubiKey: YubiKey?
    
    static func make(dbRef: URLReference) -> UIViewController {
        let vc = ChangeMasterKeyVC.instantiateFromStoryboard()
        vc.databaseRef = dbRef
        let navVC = UINavigationController(rootViewController: vc)
        navVC.modalPresentationStyle = .formSheet
        return navVC
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        databaseNameLabel.text = databaseRef.info.fileName
        databaseIcon.image = UIImage.databaseIcon(for: databaseRef)
        
        passwordField.invalidBackgroundColor = nil
        repeatPasswordField.invalidBackgroundColor = nil
        keyFileField.invalidBackgroundColor = nil
        passwordField.delegate = self
        passwordField.validityDelegate = self
        repeatPasswordField.delegate = self
        repeatPasswordField.validityDelegate = self
        keyFileField.delegate = self
        keyFileField.validityDelegate = self
        setupHardwareKeyPicker()
        
        // make background image
        view.backgroundColor = UIColor(patternImage: UIImage(asset: .backgroundPattern))
        view.layer.isOpaque = false
        
        // Initially all fields are empty, so disable the Doen button.
        navigationItem.rightBarButtonItem?.isEnabled = false
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        passwordField.becomeFirstResponder()
    }
    
    // MARK: - YubiKey
    
    private func setupHardwareKeyPicker() {
        keyFileField.yubikeyHandler = {
            [weak self] (field) in
            guard let self = self else { return }
            let popoverAnchor = PopoverAnchor(
                sourceView: self.keyFileField,
                sourceRect: self.keyFileField.bounds)
            self.showYubiKeyPicker(at: popoverAnchor)
        }
    }
    
    private func showYubiKeyPicker(at popoverAnchor: PopoverAnchor) {
        let hardwareKeyPicker = HardwareKeyPicker.create(delegate: self)
        hardwareKeyPicker.modalPresentationStyle = .popover
        if let popover = hardwareKeyPicker.popoverPresentationController {
            popoverAnchor.apply(to: popover)
            popover.delegate = hardwareKeyPicker.dismissablePopoverDelegate
        }
        hardwareKeyPicker.key = yubiKey
        present(hardwareKeyPicker, animated: true, completion: nil)
    }
    
    /// Handles challenge-response interaction
    func challengeHandler(challenge: SecureByteArray, responseHandler: @escaping ResponseHandler) {
        guard let yubiKey = yubiKey else {
            Diag.debug("Challenge-response is not used")
            responseHandler(SecureByteArray(), nil)
            return
        }
        ChallengeResponseManager.instance.perform(
            with: yubiKey,
            challenge: challenge,
            responseHandler: responseHandler
        )
    }
    
    // MARK: - Actions
    
    @IBAction func didPressCancel(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func didPressSaveChanges(_ sender: Any) {
        guard let db = DatabaseManager.shared.database else {
            assertionFailure()
            return
        }
        
        let _challengeHandler = (yubiKey != nil) ? challengeHandler : nil
        DatabaseManager.createCompositeKey(
            keyHelper: db.keyHelper,
            password: passwordField.text ?? "",
            keyFile: keyFileRef,
            challengeHandler: _challengeHandler,
            success: {
                [weak self] (_ newCompositeKey: CompositeKey) -> Void in
                guard let _self = self else { return }
                let dbm = DatabaseManager.shared
                dbm.changeCompositeKey(to: newCompositeKey)
                try? dbm.rememberDatabaseKey(onlyIfExists: true) // throws KeychainError, ignored
                dbm.addObserver(_self)
                dbm.startSavingDatabase(challengeHandler: _challengeHandler)
            },
            error: {
                [weak self] (_ errorMessage: String) -> Void in
                guard let _self = self else { return }
                Diag.error("Failed to create new composite key [message: \(errorMessage)]")
                let errorAlert = UIAlertController.make(
                    title: LString.titleError,
                    message: errorMessage)
                _self.present(errorAlert, animated: true, completion: nil)
            }
        )
    }
    
    // MARK: - Progress tracking
    
    private var progressOverlay: ProgressOverlay?
    fileprivate func showProgressOverlay() {
        progressOverlay = ProgressOverlay.addTo(
            view, title: LString.databaseStatusSaving, animated: true)
        progressOverlay?.isCancellable = true
        
        // Temporarily disable navigation
        if #available(iOS 13, *) {
            isModalInPresentation = true
        }
        navigationItem.leftBarButtonItem?.isEnabled = false
        navigationItem.rightBarButtonItem?.isEnabled = false
        navigationItem.hidesBackButton = true
    }
    
    fileprivate func hideProgressOverlay() {
        UIView.animateKeyframes(
            withDuration: 0.2,
            delay: 0.0,
            options: [.beginFromCurrentState],
            animations: {
                [weak self] in
                self?.progressOverlay?.alpha = 0.0
            },
            completion: {
                [weak self] finished in
                guard let _self = self else { return }
                _self.progressOverlay?.removeFromSuperview()
                _self.progressOverlay = nil
            }
        )
        // Enable navigation
        if #available(iOS 13, *) {
            isModalInPresentation = false
        }
        navigationItem.leftBarButtonItem?.isEnabled = true
        navigationItem.rightBarButtonItem?.isEnabled = true
        navigationItem.hidesBackButton = false
    }
}

extension ChangeMasterKeyVC: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case passwordField:
            repeatPasswordField.becomeFirstResponder()
        case repeatPasswordField:
            didPressSaveChanges(self)
        default:
            break
        }
        return true
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        if textField === keyFileField {
            passwordField.becomeFirstResponder()
            let keyFileChooserVC = ChooseKeyFileVC.make(
                popoverSourceView: keyFileField,
                delegate: self)
            present(keyFileChooserVC, animated: true, completion: nil)
        }
    }
}

extension ChangeMasterKeyVC: ValidatingTextFieldDelegate {
    func validatingTextFieldShouldValidate(_ sender: ValidatingTextField) -> Bool {
        switch sender {
        case passwordField, keyFileField:
            let gotPassword = passwordField.text?.isNotEmpty ?? false
            let gotKeyFile = keyFileRef != nil
            return gotPassword || gotKeyFile
        case repeatPasswordField:
            let isPasswordsMatch = (passwordField.text == repeatPasswordField.text)
            UIView.animate(withDuration: 0.5) {
                self.passwordMismatchImage.alpha = isPasswordsMatch ? 0.0 : 1.0
            }
            return isPasswordsMatch
        default:
            return true
        }
    }
    
    func validatingTextField(_ sender: ValidatingTextField, textDidChange text: String) {
        if sender === passwordField {
            repeatPasswordField.validate()
        }
    }
    
    func validatingTextField(_ sender: ValidatingTextField, validityDidChange isValid: Bool) {
        let allValid = passwordField.isValid && repeatPasswordField.isValid && keyFileField.isValid
        navigationItem.rightBarButtonItem?.isEnabled = allValid
    }
}

extension ChangeMasterKeyVC: KeyFileChooserDelegate {
    func onKeyFileSelected(urlRef: URLReference?) {
        // can be nil, can have error, can be ok
        keyFileRef = urlRef
        DatabaseSettingsManager.shared.updateSettings(for: databaseRef) { (dbSettings) in
            dbSettings.maybeSetAssociatedKeyFile(keyFileRef)
        }
        
        guard let keyFileRef = urlRef else {
            keyFileField.text = ""
            return
        }
        
        if let errorMessage = keyFileRef.info.errorMessage {
            keyFileField.text = ""
            let errorAlert = UIAlertController.make(
                title: LString.titleError,
                message: errorMessage)
            present(errorAlert, animated: true, completion: nil)
        } else {
            keyFileField.text = keyFileRef.info.fileName
        }
    }
}

// MARK: - HardwareKeyPickerDelegate
extension ChangeMasterKeyVC: HardwareKeyPickerDelegate {
    func didPressCancel(in picker: HardwareKeyPicker) {
        // ignored
    }
    func didSelectKey(yubiKey: YubiKey?, in picker: HardwareKeyPicker) {
        setYubiKey(yubiKey)
    }
    
    func setYubiKey(_ yubiKey: YubiKey?) {
        self.yubiKey = yubiKey
        keyFileField.isYubiKeyActive = (yubiKey != nil)

        DatabaseSettingsManager.shared.updateSettings(for: databaseRef) { (dbSettings) in
            dbSettings.maybeSetAssociatedYubiKey(yubiKey)
        }
        if let _yubiKey = yubiKey {
            Diag.info("Hardware key selected [key: \(_yubiKey)]")
        } else {
            Diag.info("No hardware key selected")
        }
    }
}

extension ChangeMasterKeyVC: DatabaseManagerObserver {
    func databaseManager(willSaveDatabase urlRef: URLReference) {
        showProgressOverlay()
    }
    
    func databaseManager(didSaveDatabase urlRef: URLReference) {
        DatabaseManager.shared.removeObserver(self)
        hideProgressOverlay()
        let parentVC = presentingViewController
        dismiss(animated: true, completion: {
            let alert = UIAlertController.make(
                title: LString.databaseStatusSavingDone,
                message: LString.masterKeySuccessfullyChanged,
                cancelButtonTitle: LString.actionOK)
            parentVC?.present(alert, animated: true, completion: nil)
        })
    }
    
    func databaseManager(progressDidChange progress: ProgressEx) {
        progressOverlay?.update(with: progress)
    }
    
    func databaseManager(database urlRef: URLReference, isCancelled: Bool) {
        Diag.info("Master key change cancelled")
        DatabaseManager.shared.removeObserver(self)
        hideProgressOverlay()
    }
    
    func databaseManager(
        database urlRef: URLReference,
        savingError message: String,
        reason: String?)
    {
        let errorAlert = UIAlertController.make(title: message, message: reason)
        present(errorAlert, animated: true, completion: nil)
        
        DatabaseManager.shared.removeObserver(self)
        hideProgressOverlay()
    }
}
