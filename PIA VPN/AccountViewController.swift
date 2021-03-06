//
//  AccountViewController.swift
//  PIA VPN
//
//  Created by Davide De Rosa on 12/7/17.
//  Copyright © 2017 London Trust Media. All rights reserved.
//

import UIKit
import PIALibrary
import SwiftyBeaver

private let log = SwiftyBeaver.self

class AccountViewController: AutolayoutViewController {
    private enum Secion: Int {
        case uncredited

        case info
    }

    @IBOutlet private weak var scrollView: UIScrollView!

    @IBOutlet private weak var viewSafe: UIView!

    @IBOutlet private weak var labelEmail: UILabel!

    @IBOutlet private weak var textEmail: BorderedTextField!
    
    @IBOutlet private weak var labelUsername: UILabel!
    
    @IBOutlet private weak var textUsername: BorderedTextField!
    
    @IBOutlet private weak var labelPassword: UILabel!
    
    @IBOutlet private weak var textPassword: BorderedTextField!
    
    @IBOutlet private weak var buttonEye: UIButton!
    
    @IBOutlet private weak var labelFooterEye: UILabel!

    @IBOutlet private weak var labelFooterOther: UILabel!

    @IBOutlet weak var labelExpiryInformation: UILabel!
    
    @IBOutlet private weak var itemUpdate: UIBarButtonItem!
    
    @IBOutlet private weak var viewSeparator: UIView!
    
    @IBOutlet private weak var viewUncredited: UIView!
    
    @IBOutlet private weak var labelRestoreTitle: UILabel!
    
    @IBOutlet private weak var labelRestoreInfo: UILabel!
    
    @IBOutlet private weak var buttonRestore: UIButton!
    
    @IBOutlet private var constraintsShowUncredited: [NSLayoutConstraint]!
    
    @IBOutlet private var constraintsHideUncredited: [NSLayoutConstraint]!
    
    private var currentUser: UserAccount?

    private var canSaveAccount = false {
        didSet {
            itemUpdate.isEnabled = canSaveAccount
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = L10n.Menu.Item.account
        labelEmail.text = L10n.Account.Email.caption
        textEmail.placeholder = L10n.Account.Email.placeholder
        labelUsername.text = L10n.Account.Username.caption
        labelPassword.text = L10n.Account.Password.caption
        buttonEye.setImage(Asset.iconEye.image, for: .normal)
        itemUpdate.title = L10n.Account.Save.item
        labelFooterEye.text = L10n.Account.Eye.footer
        labelFooterOther.text = L10n.Account.Other.footer
        labelRestoreTitle.text = L10n.Account.Restore.title
        labelRestoreInfo.text = L10n.Account.Restore.description
        buttonRestore.setTitle(L10n.Account.Restore.button.uppercased(), for: .normal)

        viewSafe.layoutMargins = .zero
        textEmail.isEditable = true
        textUsername.isEditable = false
        textPassword.isEditable = false
        canSaveAccount = false
        updateEyeAccessibilityToPasswordVisibility(false)

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(redisplayAccount), name: .PIAAccountDidRefresh, object: nil)

        Client.providers.accountProvider.refreshAndLogoutUnauthorized()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    
        // update local state immediately
        redisplayAccount()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        view.endEditing(true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    
        if textEmail.text?.isEmpty ?? true {
            textEmail.becomeFirstResponder()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        establishUncreditedVisibility()
    }

    // MARK: Actions

    @IBAction private func saveChanges(_ sender: Any?) {
        guard canSaveAccount else {
            return
        }
    
        SensitiveOperation.perform(withReason: L10n.Account.Save.prompt) {
            guard let email = self.textEmail.text else {
                return
            }

            log.debug("Account: Modifying account email...")
            
            let request = UpdateAccountRequest(email: email)
            let hud = HUD()
            
            Client.providers.accountProvider.update(with: request) { (info, error) in
                hud.hide()
                
                guard let _ = info else {
                    if let error = error {
                        log.error("Account: Failed to modify account email (error: \(error))")
                    } else {
                        log.error("Account: Failed to modify account email")
                    }

                    self.textEmail.text = ""
                    let alert = Macros.alert(L10n.Global.error, error?.localizedDescription)
                    alert.addCancelAction(L10n.Global.close)
                    self.present(alert, animated: true, completion: nil)
                    
                    return
                }

                log.debug("Account: Email successfully modified")
                let alert = Macros.alert(nil, L10n.Account.Save.success)
                alert.addCancelAction(L10n.Global.ok)
                self.present(alert, animated: true, completion: nil)
                
                self.textEmail.text = email
                self.textEmail.endEditing(true)
                
                self.canSaveAccount = false
            }
        }
    }
    
    @IBAction private func togglePasswordVisibility(_ sender: Any?) {

        // conceal
        if !textPassword.isSecureTextEntry {
            textPassword.isSecureTextEntry = true
            updateEyeAccessibilityToPasswordVisibility(false)
        }
        // reveal
        else {
            SensitiveOperation.perform(withReason: L10n.Account.Reveal.prompt) {
                self.textPassword.isSecureTextEntry = false
                self.updateEyeAccessibilityToPasswordVisibility(true)
            }
        }
    }
    
    private func updateEyeAccessibilityToPasswordVisibility(_ passwordVisibility: Bool) {
        buttonEye.accessibilityLabel = L10n.Account.Accessibility.eye
        let hint: String
        if passwordVisibility {
            hint = L10n.Account.Accessibility.Eye.Hint.conceal
        } else {
            hint = L10n.Account.Accessibility.Eye.Hint.reveal
        }
        buttonEye.accessibilityHint = hint
    }
    
    @IBAction private func renewSubscriptionWithUncreditedPurchase(_ sender: Any?) {
        Client.providers.accountProvider.restorePurchases { (error) in
            if let error = error {
                self.handleReceiptFailureWithError(error)
                return
            }
            self.handleReceiptRefresh()
        }
    }
    
    private func handleReceiptRefresh() {
        log.debug("IAP: Restored payment receipt, redeeming...")

        Client.providers.accountProvider.renew(with: RenewRequest(transaction: nil)) { (user, error) in
            if let clientError = error as? ClientError, (clientError == .badReceipt) {
                self.handleBadReceipt()
                return
            }
            self.handleReceiptSubmissionWithError(error)
        }
    }
        
    private func handleReceiptFailureWithError(_ error: Error?) {
        log.error("IAP: Failed to restore payment receipt (error: \(error?.localizedDescription ?? ""))")

        let alert = Macros.alert(L10n.Global.error, error?.localizedDescription)
        alert.addCancelAction(L10n.Global.close)
        present(alert, animated: true, completion: nil)
    }
    
    private func handleReceiptSubmissionWithError(_ error: Error?) {
        if let error = error {
            let alert = Macros.alert(L10n.Global.error, error.localizedDescription)
            alert.addCancelAction(L10n.Global.close)
            present(alert, animated: true, completion: nil)
            return
        }

        log.debug("Account: Renewal successfully completed")
        
        let alert = Macros.alert(
            L10n.Renewal.Success.title,
            L10n.Renewal.Success.message
        )
        alert.addCancelAction(L10n.Global.close)
        present(alert, animated: true, completion: nil)

        redisplayAccount()
    }
    
    private func handleBadReceipt() {
        let alert = Macros.alert(
            L10n.Account.Restore.Failure.title,
            L10n.Account.Restore.Failure.message
        )
        alert.addCancelAction(L10n.Global.close)
        present(alert, animated: true, completion: nil)
    }

    // MARK: Notifications

    @objc private func redisplayAccount() {
        currentUser = Client.providers.accountProvider.currentUser

        textEmail.endEditing(true)
        textEmail.text = currentUser?.info?.email
        textEmail.isEnabled = !(currentUser?.info?.isExpired ?? true)
        textUsername.text = currentUser?.credentials.username
        textPassword.text = currentUser?.credentials.password
        
        if let userInfo = currentUser?.info {
            if userInfo.isExpired {
                labelExpiryInformation.text = L10n.Account.ExpiryDate.expired
            } else {
                labelExpiryInformation.text = L10n.Account.ExpiryDate.information(userInfo.humanReadableExpirationDate())
            }
            styleExpirationDate()
        }
        
        establishUncreditedVisibility()
    }
    
    private func establishUncreditedVisibility() {
        if let info = currentUser?.info, (info.isRenewable && !info.isExpired) {
            NSLayoutConstraint.deactivate(constraintsHideUncredited)
            NSLayoutConstraint.activate(constraintsShowUncredited)
            viewSeparator.isHidden = false
            viewUncredited.isHidden = false
        } else {
            NSLayoutConstraint.deactivate(constraintsShowUncredited)
            NSLayoutConstraint.activate(constraintsHideUncredited)
            viewSeparator.isHidden = true
            viewUncredited.isHidden = true
        }
    }

    // MARK: Restylable
    
    override func viewShouldRestyle() {
        super.viewShouldRestyle()
        
        for label in [labelEmail!, labelUsername!, labelPassword!] {
            Theme.current.applyLabel(label, appearance: .dark)
        }
        Theme.current.applyInput(textEmail)
        Theme.current.applyInput(textUsername)
        Theme.current.applyInput(textPassword)
        Theme.current.applyDivider(viewSeparator)
        for label in [labelFooterEye!, labelFooterOther!, labelExpiryInformation!] {
            Theme.current.applySmallInfo(label, appearance: .dark)
        }
        Theme.current.applyBody2(labelRestoreTitle, appearance: .dark)
        Theme.current.applyBody1(labelRestoreInfo, appearance: .dark)
        Theme.current.applyTextButton(buttonRestore)
        
        styleExpirationDate()
        
    }
    
    private func styleExpirationDate() {
        if let userInfo = currentUser?.info {
            Theme.current.makeSmallLabelToStandOut(labelExpiryInformation,
                                                   withTextToStandOut: userInfo.humanReadableExpirationDate())
        }
    }
}

extension AccountViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let hitEnter = (string == "\n")
        if !hitEnter {
            if let currentText = textField.text {
                let newText = (currentText as NSString).replacingCharacters(in: range, with: string)
                canSaveAccount = ((newText != currentUser?.info?.email) && Validator.validate(email: newText))
            }
        }
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if (textField == textEmail) {
            textField.resignFirstResponder()
            saveChanges(textField)
        }
        return true
    }
}
