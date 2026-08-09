import SwiftUI

@main
struct RPGPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            Text(AppMetadata.displayName)
                .preferredColorScheme(.dark)
        }
    }
}
