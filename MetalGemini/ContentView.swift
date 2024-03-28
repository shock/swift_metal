//
//  ContentView.swift
//  MetalGemini
//
//  Created by Gemini on 3/27/24.
//

import SwiftUI
import MetalKit

struct AppMenuKey: EnvironmentKey {
    static let defaultValue: NSMenu? = nil // Default value of nil
}

// Add an extension for your environment key:
extension EnvironmentValues {
    var appMenu: NSMenu? {
        get { self[AppMenuKey.self] }
        set { self[AppMenuKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(\.appMenu) var appMenu // Property for holding menu reference

    var body: some View {
        MetalView()
            .environment(\.appMenu, appDelegate.mainMenu) // Add menu to the environment
    }
}

#Preview {
    ContentView()
}
