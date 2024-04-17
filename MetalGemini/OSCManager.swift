//
//  OSCManager.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/17/24.
//

import Foundation
import SwiftUI
import SwiftOSC

class OSCServerManager: ObservableObject {
    var server: OSCServer
    var metalView: MetalView.Coordinator!

    init(metalView: MetalView.Coordinator) {
        server = OSCServer(address: "", port: 8000)
        server.delegate = self
        self.metalView = metalView
    }

    func startServer() {
        server.start()
    }

    func stopServer() {
        server.stop()
    }
}

extension OSCServerManager: OSCServerDelegate {
    func didReceive(_ message: OSCMessage) {
        DispatchQueue.main.async {
            self.metalView.recvOscMsg(message)
        }
    }
}
