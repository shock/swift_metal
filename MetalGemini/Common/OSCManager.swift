//
//  OSCManager.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/17/24.
//

import Foundation
import SwiftUI
import SwiftOSC

protocol OSCMessageDelegate {
    func handleOSCMessage(message: OSCMessage)
}

class OSCServerManager: ObservableObject {
    var server: OSCServer
    var delegate: OSCMessageDelegate?

    init(delegate: OSCMessageDelegate) {
        server = OSCServer(address: "", port: 8000)
        server.delegate = self
        self.delegate = delegate
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
            self.delegate?.handleOSCMessage(message: message)
        }
    }
}
