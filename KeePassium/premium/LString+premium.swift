//  KeePassium Password Manager
//  Copyright © 2018–2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

extension LString {
    
    public static let errorNoPurchasesAvailable = NSLocalizedString(
        "[Premium/Upgrade] Hmm, there are no upgrades available. This should not happen, please contact support.",
        value: "Hmm, there are no upgrades available. This should not happen, please contact support.",
        comment: "Error message: AppStore returned no available in-app purchase options")
    
    public static let subscriptionConditions = NSLocalizedString(
        "[Premium/Subscription/Legal/text]",
        value:
            """
            Payment will be charged to your Apple ID account at the confirmation of purchase.
            
            Subscription automatically renews unless it is canceled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period.
            
            You can manage and cancel your subscriptions by going to your account settings on the App Store after purchase.
            """,
        comment: "Subscription conditions")
    
    
    // MARK: Pricing plans

    public static let premiumFreePlanTitle = NSLocalizedString(
        "[Premium/Price Plan/Free/title]",
        value: "Free",
        comment: "Name of the free pricing plan")
    public static let premiumFreePlanPrice = NSLocalizedString(
        "[Premium/Price Plan/Free/price]",
        value: "Free",
        comment: "Price of the free pricing plan")
    
    public static let priceTemplateMonthly = NSLocalizedString(
        "[Premium/Upgrade/price] %@ / month",
        value: "%@ / month",
        comment: "Product price for monthly premium subscription. [localizedPrice: String]")
    public static let priceTemplateYearly = NSLocalizedString(
        "[Premium/Upgrade/price] %@ / year",
        value: "%@ / year",
        comment: "Product price for annual premium subscription. [localizedPrice: String]")
    public static let priceTemplateOnce = NSLocalizedString(
        "[Premium/Upgrade/price] %@ once",
        value: "%@ once",
        comment: "Product price for once-and-forever premium. [localizedPrice: String]")
    public static let trialConditionsTemplate = NSLocalizedString(
        "[Premium/Trial/trial then price]",
        value: "Free trial for %@, then %@",
        comment: "Trial conditions. For example `Free trial for 30 days, then $1 per month`")
    
    public static let premiumWhatYouGet = NSLocalizedString(
        "[Premium/Benefits/Positive/header] ",
        value: "What you get",
        comment: "List of premium benefits/advantages")
    public static let premiumWhatYouMiss = NSLocalizedString(
        "[Premium/Benefits/Negative/header] ",
        value: "What you are missing",
        comment: "List of premium benefits/advantages")
    
    // MARK: Purchase call for action
    
    public static let premiumCallToActionFree = NSLocalizedString(
        "[Premium/CallToAction/free]",
        value: "Continue Testing",
        comment: "Call to action: continue using the free version")
    public static let premiumCallToActionStartTrial = NSLocalizedString(
        "[Premium/CallToAction/startTrial]",
        value: "Start Free Trial",
        comment: "Call to action: upgrade to premium")
    public static let premiumCallToActionUpgradeNow = NSLocalizedString(
        "[Premium/CallToAction/upgradeNow]",
        value: "Upgrade Now",
        comment: "Call to action: upgrade to premium")

    // MARK: App Store communication status
    
    public static let statusContactingAppStore = NSLocalizedString(
        "[Premium/Upgrade/Progress] Contacting AppStore...",
        value: "Contacting AppStore...",
        comment: "Status message when downloading available in-app purchases")
    public static let statusPurchasing = NSLocalizedString(
        "[Premium/Upgrade/Progress] Purchasing...",
        value: "Purchasing...",
        comment: "Status: in-app purchase started")
    public static let statusDeferredPurchase = NSLocalizedString(
        "[Premium/Upgrade/Deferred/text] Thank you! You can use KeePassium while purchase is awaiting approval from a parent",
        value: "Thank you! You can use KeePassium while purchase is awaiting approval from a parent",
        comment: "Message shown when in-app purchase is deferred until parental approval.")


    // MARK: Restoring purchases
    
    public static let titlePurchaseRestored = NSLocalizedString(
        "[Premium/Upgrade/Restored/title] Purchase Restored",
        value: "Purchase Restored",
        comment: "Title of the message shown after in-app purchase was successfully restored")
    public static let purchaseRestored = NSLocalizedString(
        "[Premium/Upgrade/Restored/text] Upgrade successful, enjoy the app!",
        value: "Upgrade successful, enjoy the app!",
        comment: "Text of the message shown after in-app purchase was successfully restored")
    
    public static let titleRestorePurchaseError = NSLocalizedString(
        "[Premium/Upgrade/RestoreFailed/title] Sorry",
        value: "Sorry",
        comment: "Title of an error message: there were no in-app purchases that can be restored")
    public static let errorNoPreviousPurchaseToRestore = NSLocalizedString(
        "[Premium/Upgrade/RestoreFailed/text] No previous purchase could be restored.",
        value: "No previous purchase could be restored.",
        comment: "Text of an error message: there were no in-app purchases that can be restored")
    

}
