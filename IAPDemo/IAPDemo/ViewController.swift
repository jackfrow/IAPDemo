//
//  ViewController.swift
//  IAPDemo
//
//  Created by jackfrow on 2021/6/8.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        IAPTool.shared.loadAllProducts(products: ["com.problenchild.YQIAPTest.product1",
                                                  "com.problenchild.YQIAPTest.product2",
                                                  "com.problenchild.YQIAPTest.product3"])
        
    }


}

