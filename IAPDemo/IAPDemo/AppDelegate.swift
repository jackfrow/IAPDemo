//
//  AppDelegate.swift
//  IAPDemo
//
//  Created by jackfrow on 2021/6/8.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {


    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        IAPManager.shared.initializeNotifications()

        return true
    }
    
    
    

}

