//
//  igc2csv_documentApp.swift
//  igc2csv_document
//
//  Created by Alonzo Kelly on 12/8/25.
//

import SwiftUI

@main
struct igc2csv_documentApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        #endif
    }
}
