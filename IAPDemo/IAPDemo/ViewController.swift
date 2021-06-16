//
//  ViewController.swift
//  IAPDemo
//
//  Created by jackfrow on 2021/6/8.
//

import UIKit
import MBProgressHUD

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        initializeNotifications()
    }
    
    
    private func initializeNotifications() {

        // purchase succeed
        NotificationCenter.default.addObserver(forName: NSNotification.Name.mkStoreKitProductPurchased, object: nil, queue: OperationQueue.main) {  (notification) in
            NSLog("[PAYMENT SET] purchased SUCCEED.")
            MBProgressHUD.hide(for: self.view, animated: true)
        }

        // purchase failed
        NotificationCenter.default.addObserver(forName: NSNotification.Name.mkStoreKitProductPurchaseFailed, object: nil, queue: OperationQueue.main) {  (notification) in
            NSLog("[PAYMENT SET] purchased FAILED.")
            MBProgressHUD.hide(for: self.view, animated: true)

        }

        // dismiss
        NotificationCenter.default.addObserver(forName: CLEAR_ALL_PURCHASE_PAGE, object: nil, queue: OperationQueue.main) { [weak self] (notification) in

            self?.dismiss(animated: true, completion: nil)
        }
    }

    
    @IBAction func bug(_ sender: Any) {
        
        
        MBProgressHUD.showAdded(to: self.view, animated: true)
        
        MKStoreKit.shared()?.initiatePaymentRequestForProduct(withIdentifier: "monthly_vip_trial")
        
    }
    
    
    
    @IBAction func restore(_ sender: Any) {
    }
    

}



