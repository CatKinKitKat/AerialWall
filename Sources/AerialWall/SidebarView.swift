import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    let count: Int
    @AppStorage("aerialwall.developerMode") private var developerMode = false

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("All Wallpapers", systemImage: "photo.on.rectangle.angled")
                    .tag(SidebarItem.allWallpapers)
                    .badge(count)
                Label("Recently Added", systemImage: "clock")
                    .tag(SidebarItem.recentlyAdded)
            }
            if developerMode {
                Section("Developer") {
                    Label("Logs", systemImage: "terminal")
                        .tag(SidebarItem.logs)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }
}
