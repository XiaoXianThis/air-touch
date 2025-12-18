//
//  touch_client_iosApp.swift
//  touch-client-ios
//
//  Created by mac on 2025/12/18.
//

import SwiftUI

@main
struct touch_client_iosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .defersSystemGestures(on: .all)  // 延迟系统手势，需要二次确认
        }
    }
}

// 自定义 AppDelegate 处理屏幕方向和系统手势
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .landscape
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // 隐藏 Home Indicator 自动隐藏延迟
        return true
    }
}
