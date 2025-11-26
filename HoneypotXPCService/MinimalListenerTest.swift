//
//  MinimalListenerTest.swift
//  HoneypotXPCService
//

import Foundation
import Network

class MinimalListenerTest {
    private var listener: NWListener?

    func runTest() {
        do {
            let params = NWParameters.tcp
            params.acceptLocalOnly = false
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: 9999)

            listener?.stateUpdateHandler = { _ in }

            listener?.newConnectionHandler = { connection in
                connection.stateUpdateHandler = { _ in }
                connection.start(queue: .global())

                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    connection.cancel()
                }
            }

            listener?.start(queue: .global())

        } catch {
        }
    }

    func stopTest() {
        listener?.cancel()
    }
}
