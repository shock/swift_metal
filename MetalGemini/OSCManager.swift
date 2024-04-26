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
    var uniformManager: UniformManager!

    init(uniformManager: UniformManager) {
        server = OSCServer(address: "", port: 8000)
        server.delegate = self
        self.uniformManager = uniformManager
    }

    func startServer() {
        server.start()
    }

    func stopServer() {
        server.stop()
    }

    deinit {
        stopServer()
    }
}

extension OSCServerManager: OSCServerDelegate {
    func didReceive(_ message: OSCMessage) {
        DispatchQueue.main.async {
            self.uniformManager.recvOscMsg(message)
        }
    }
}
