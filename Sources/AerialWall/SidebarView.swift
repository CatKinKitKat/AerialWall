import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    let count: Int
    @AppStorage("aerialwall.developerMode") private var developerMode = false

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                NavigationLink(value: SidebarItem.allWallpapers) {
                    Label("All Wallpapers", systemImage: "photo.on.rectangle.angled")
                        .badge(count)
                }
                NavigationLink(value: SidebarItem.recentlyAdded) {
                    Label("Recently Added", systemImage: "clock")
                }
            }
            if developerMode {
                Section("Developer") {
                    NavigationLink(value: SidebarItem.logs) {
                        Label("Logs", systemImage: "terminal")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }
}
