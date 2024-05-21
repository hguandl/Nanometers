//
//  NanometersApp.swift
//  Nanometers
//
//  Created by hguandl on 2024/5/21.
//

import CoreMIDI
import SwiftUI

@main
struct NanometersApp: App {
    @ObservedObject private var hostModel = AudioUnitHostModel()

    var body: some Scene {
        WindowGroup {
            ContentView(hostModel: hostModel)
        }
    }
}
