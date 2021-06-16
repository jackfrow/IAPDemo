//
//  IAPManager.swift
//  IAPDemo
//
//  Created by jackfrow on 2021/6/16.
//

import UIKit
import StoreKit

let CLEAR_ALL_PURCHASE_PAGE = Notification.Name(rawValue: "CLEAR_ALL_PURCHASE_PAGE")

enum IAPProduct: String {
    case monthly = "speedvpn_monthly"
}

class IAPManager: NSObject {
    
    
    // Singleton
    static let shared = IAPManager()
    override init() {
        super.init()
        MKStoreKit.shared()?.startProductRequest()
        MKStoreKit.shared()?.loadReceiptData()
        if let _ = MKStoreKit.shared()?.receiptData {
            NSLog("[IAP] has receipt data, start validation.")
            self.validatingReceiptViaAppStore()
        } else {
            NSLog("[IAP] no receipt data")
        }
    }
    
    
    var lastestReceipt: [String: Any]?  {
        didSet {
//            SharingInfo.setReceipt(receipt: lastestReceipt)
//            SharingInfo.setTransactionIdentifier(identifier: lastestReceipt?["transaction_id"] as? String)
//            NSLog("[IAP] RECEIPT: \(SharingInfo.getReceipt()?.description ?? "none")")
        }
    }
    
    var hasValidPurchase: Bool {
        get {
            return false
//            // if valid
//            if let expires_date_ms = lastestReceipt?["expires_date_ms"], NSString(string: "\(expires_date_ms)").doubleValue > APPConfigs.shared.currentTimestamp {
//                return true
//            } else {
//                return false
//            }
        }
    }
    
    var isNewPurchase: Bool {
        get {
//            if let original_order_id = lastestReceipt?["original_transaction_id"] as? String, let order_id = SharingInfo.getTransactionIdentifier(), original_order_id != order_id {
//                return false
//            }
            return false
        }
    }
    
    
    private var restoreHandler: (([[String: String]]?, String?) -> Void)?

}



// MARK: - Private methods

extension IAPManager {

    func validatingReceiptViaAppStore(fromRestore: Bool = false, handler: (([[String: Any]]?, Error?) -> Void)? = nil) {

        MKStoreKit.shared()?.validatingAppStoreReceipt(completionHandler: { (receipts, error) in
            // succeed
            if receipts?.count ?? 0 > 0 {
                NSLog("[IAP] RECEIPT: ********************************")
                if let receipts = receipts as? [[String: Any]] {
                    for receipt in receipts {
                        NSLog("[IAP] id: \(receipt["transaction_id"] ?? "none"), expire: \(receipt["expires_date"] ?? receipt["expires_date_ms"] ?? "none")")
                    }
                    self.lastestReceipt = receipts.last
                }
                NSLog("[IAP] *****************************************")
            } else {
                if let error = error {
                    NSLog("[IAP] receipt validate failed: \(error.localizedDescription).")
                } else {
                    NSLog("[IAP] RECEIPT: no purchase record.")
                    if fromRestore {
                        NSLog("[IAP] RECEIPT: clear receipt & transaction id.")
                        self.lastestReceipt = nil
                    }
                }
            }
            // handler
            handler?(receipts as? [[String : Any]], error)
        })
    }
}


// MARK: - Public methods
extension IAPManager {

    func initializeNotifications() {

        // purchase succeed
        NotificationCenter.default.addObserver(forName: NSNotification.Name.mkStoreKitProductPurchased, object: nil, queue: OperationQueue.main) { (notification) in

            NSLog("[IAP] PURCHASE succeed: \(notification.object ?? "unknown") - \(notification.userInfo?["transactionIdentifier"] ?? "unknown")")

            // validate receipt
//            self.state = .purchased
            self.validatingReceiptViaAppStore { (receipts, error) in
                if let _ = error { } else {
                
                }
            }
//            SharingInfo.setTransactionIdentifier(identifier: notification.userInfo?["transactionIdentifier"] as? String)
//            NotificationCenter.default.post(name: SUBSCRIPTION_SUCCEED, object: notification.object, userInfo: notification.userInfo)
        }

        // purchase failed
        NotificationCenter.default.addObserver(forName: NSNotification.Name.mkStoreKitProductPurchaseFailed, object: nil, queue: OperationQueue.main) { (notification) in

            NSLog("[IAP] PURCHASE falied: \(notification.object ?? "unknown") - \(notification.userInfo?["message"] ?? "unknown")")
        }

        // restore succeed
        NotificationCenter.default.addObserver(forName: NSNotification.Name.mkStoreKitRestoredPurchases, object: nil, queue: OperationQueue.main) { (notification) in

            NSLog("[IAP] RESTORE succeed: \n\(notification.userInfo?["restoredPurchases"] ?? "unknown")")
            // has record
            if let purchases = notification.userInfo?["restoredPurchases"] as? [[String: String]], purchases.count > 0 {
                NSLog("[IAP] RESTORE has record, start validation.")
                self.validatingReceiptViaAppStore(fromRestore: true)
                self.restoreHandler?(purchases, nil)
            } else {
                NSLog("[IAP] RESTORE no record.")
                self.lastestReceipt = nil
                self.restoreHandler?(nil, nil)
                MKStoreKit.shared()?.refreshAppStoreReceipt()
            }
            self.restoreHandler = nil
        }

        // restore failed
        NotificationCenter.default.addObserver(forName: NSNotification.Name.mkStoreKitRestoringPurchasesFailed, object: nil, queue: OperationQueue.main) { (notification) in

            NSLog("[IAP] RESTORE falied: \(notification.userInfo?["message"] ?? "unknown")")
            self.restoreHandler?(nil, "\(notification.userInfo?["message"] ?? "unknown")")
            self.restoreHandler = nil
        }
    }

    func restorePurchase(completionHandler:(([[String: String]]?, String?) -> Void)?) {

        self.restoreHandler = completionHandler
        MKStoreKit.shared()?.restorePurchases()
    }

    func broadcastClearPurchaseNotification() {

        NotificationCenter.default.post(name: CLEAR_ALL_PURCHASE_PAGE, object: nil)
    }

    class func isProductAvailable(_ product: IAPProduct) -> Bool {

        for sk_product in MKStoreKit.shared()?.availableProducts ?? [SKProduct]() {
            if product.rawValue == sk_product.productIdentifier {
                return true
            }
        }
        return false
    }
}
