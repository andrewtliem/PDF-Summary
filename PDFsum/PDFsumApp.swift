//
//  PDFsumApp.swift
//  PDFsum
//
//  Created by Andrew Tanny Liem on 08/07/25.
//

import SwiftUI
import SwiftData

@main
struct PDFsumApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [PersistentContentSummary.self, AppSettings.self])
    }
}
