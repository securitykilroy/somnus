//
//  Somnus_Watch_AppApp.swift
//  Somnus Watch App Watch App
//
//  Created by Ric Messier on 5/28/26.
//

import SwiftUI

@main
struct Somnus_Watch_App_Watch_AppApp: App {
    @State private var store = WatchSomnusStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
