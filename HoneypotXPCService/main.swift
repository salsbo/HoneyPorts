//
//  main.swift
//  HoneypotXPCService
//

import Foundation

class XPCServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: HoneypotXPCProtocol.self)
        newConnection.exportedObject = ListenerManager.shared
        newConnection.resume()
        return true
    }
}

let delegate = XPCServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()

let globalMinimalTest = MinimalListenerTest()
globalMinimalTest.runTest()

dispatchMain()
