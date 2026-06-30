import CoLearnerCore
import AppKit
import SwiftUI

@main
struct CoLearnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = ReaderViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1080, minHeight: 720)
                .onAppear {
                    AppActivation.bringToFront()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF...") {
                    viewModel.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandMenu("Assistant") {
                ForEach(StudyMode.allCases) { mode in
                    Button(mode.label) {
                        viewModel.requestResponse(mode: mode)
                    }
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppActivation.bringToFront()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

enum AppActivation {
    @MainActor
    static func bringToFront() {
        NSApplication.shared.setActivationPolicy(.regular)

        DispatchQueue.main.async {
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
