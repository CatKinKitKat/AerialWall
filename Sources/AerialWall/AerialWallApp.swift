import SwiftUI
import AerialWallKit

@main
struct AerialWallApp: App {
    var body: some Scene {
        WindowGroup("AerialWall") {
            ContentView()
                .frame(minWidth: 640, minHeight: 480)
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Text("AerialWall")
                .font(.largeTitle)
            Text("v\(AerialWallKit.version)")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
