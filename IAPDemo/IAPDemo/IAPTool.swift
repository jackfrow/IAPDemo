//
//  IAPTool.swift
//  IAPDemo
//
//  Created by jackfrow on 2021/6/8.
//

import Foundation
import StoreKit

class IAPTool:NSObject {
    
    static let shared = IAPTool()
    
    func loadAllProducts(products:[String])  {
        if products.count <= 0 {
            print("empty products")
            return
        }
        
        let set = Set(products)
        print("set",set)
        let request = SKProductsRequest.init(productIdentifiers: set)
        request.delegate = self
        request.start()

    }
    
}

extension IAPTool:SKProductsRequestDelegate{
 
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
         print("productsRequest didReceive response")
        print("response",response.products)
        print("invalidProductIdentifiers",response.invalidProductIdentifiers)
    }
    
    func requestDidFinish(_ request: SKRequest) {
        print("requestDidFinish")
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        print("request didFailWithError \(error)")
    }
    
}


