//
//  AppDelegate.swift
//  HoneyPorts
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem!
    var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("HoneyPortsMenuBar")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "🍯"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "HoneyPorts Loading...", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        menuBarController = MenuBarController(existingStatusItem: statusItem)
    }

    func applicationWillTerminate(_ notification: Notification) {
    }
}
