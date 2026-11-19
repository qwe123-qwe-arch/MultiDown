import SwiftUI

@main
struct MultiDownApp: App {
    @StateObject private var store = DownloadStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
