import SwiftUI

@main
struct VertoApp: App {
    @StateObject private var vm = VertoViewModel()        // single source of truth

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .preferredColorScheme(vm.theme.colorScheme)
                .tint(vm.theme.accent)
        }
    }
}
