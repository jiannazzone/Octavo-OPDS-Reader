#if DEBUG
import SwiftUI
import UIKit

/// THROWAWAY (step 1 of #6): does SwiftUI's `TabView` render the Duo's
/// side-column tab bar? Launch with `-probe 1`, plus `-probeStyle
/// automatic|sidebarAdaptable|tabBarOnly` and `-probeTab home|library|settings|search`.
/// The Library tab has three pages: a list, a full-screen cover (D4) and a
/// reader stand-in with side-column controls (D7), picked by `-probePage`.
struct TabBarProbe: View {
    @AppStorage("probeStyle") private var style = "automatic"
    @AppStorage("probeTab") private var tab = "home"
    @AppStorage("probeSearchOnTabView") private var searchOnTabView = false
    @AppStorage("probeMinimize") private var minimize = false
    @State private var query = ""

    var body: some View {
        Group {
            switch style {
            case "uikit": UIKitTabsProbe().ignoresSafeArea()
            case "sidebarAdaptable": tabs.tabViewStyle(.sidebarAdaptable)
            case "tabBarOnly": tabs.tabViewStyle(.tabBarOnly)
            default: tabs
            }
        }
        .modifier(SearchOnTabView(enabled: searchOnTabView, query: $query))
        .tabBarMinimizeBehavior(minimize ? .onScrollDown : .automatic)
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: "home") {
                NavigationStack { ProbeReadout(title: "Home") }
            }
            Tab("Library", systemImage: "books.vertical", value: "library") {
                ProbeLibrary()
            }
            Tab("Settings", systemImage: "gear", value: "settings") {
                NavigationStack { ProbeReadout(title: "Settings") }
            }
            Tab(value: "search", role: .search) {
                ProbeSearch()
            }
        }
    }
}

/// The same four tabs through UIKit's `UITabBarController` and `UISearchTab`.
private struct UIKitTabsProbe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UITabBarController {
        func page(_ title: String) -> UIViewController {
            UINavigationController(rootViewController: UIHostingController(rootView: ProbeReadout(title: title)))
        }
        let controller = UITabBarController()
        controller.tabs = [
            UITab(title: "Home", image: UIImage(systemName: "house"), identifier: "home") { _ in page("Home") },
            UITab(title: "Library", image: UIImage(systemName: "books.vertical"), identifier: "library") { _ in page("Library") },
            UITab(title: "Settings", image: UIImage(systemName: "gear"), identifier: "settings") { _ in page("Settings") },
            UISearchTab { _ in page("Search") },
        ]
        return controller
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {}
}

private struct SearchOnTabView: ViewModifier {
    let enabled: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if enabled { content.searchable(text: $query, prompt: "Title, author, series") } else { content }
    }
}

private struct ProbeLibrary: View {
    @AppStorage("probePage") private var page = "list"

    var body: some View {
        switch page {
        case "pairs": ProbePairs()
        case "split": ProbeSplit()
        case "twopane": ProbeTwoPane()
        default:
            NavigationStack {
                switch page {
                case "cover": ProbeCover()
                case "reader": ProbeReader()
                default: ProbeReadout(title: "Library")
                }
            }
        }
    }
}

/// One `NavigationStack` whose screens are pairs of panes split at the
/// hinge: do both panes' toolbar items and the back button go to the column?
private struct ProbePairs: View {
    @AppStorage("probePushed") private var pushed = false
    @State private var path: [Int] = []

    var body: some View {
        NavigationStack(path: $path) {
            ProbePair(left: "Collections", right: "Classics")
                .navigationDestination(for: Int.self) { _ in ProbePair(left: "Classics", right: "Moby-Dick") }
        }
        .onAppear { if pushed { path = [1] } }
    }
}

private struct ProbePair: View {
    let left: String
    let right: String

    var body: some View {
        GeometryReader { proxy in
            let division = proxy.reservedRegions(kind: .division, options: .includeInactive, layoutDirectionBehavior: .fixed).first?.frame
            HStack(spacing: 0) {
                pane(left).frame(width: division?.minX ?? proxy.size.width / 2)
                    .toolbar { ToolbarItem { Button("Filter", systemImage: "line.3.horizontal.decrease") {} } }
                Color.red.opacity(0.3).frame(width: division?.width ?? 0)
                pane(right)
                    .toolbar { ToolbarItem { Button("More", systemImage: "ellipsis") {} } }
            }
        }
        .toolbarTitleDisplayMode(.inline)
    }

    private func pane(_ title: String) -> some View {
        List {
            Text(title).font(.largeTitle.bold()).listRowBackground(Color.clear)
            ForEach(1..<10) { Text("\(title) \($0)") }
        }
    }
}

/// Does `NavigationSplitView` divide at the hinge on its own?
private struct ProbeSplit: View {
    @State private var selection: Int? = 1

    var body: some View {
        NavigationSplitView {
            List(1..<12, id: \.self, selection: $selection) { Text("Book \($0)") }
                .navigationTitle("Library")
                .toolbar { Button("Filter", systemImage: "line.3.horizontal.decrease") {} }
        } detail: {
            ProbeReadout(title: "Book \(selection ?? 0)")
                .toolbar { Button("More", systemImage: "ellipsis") {} }
        }
    }
}

/// Two `NavigationStack`s side by side, split at the hinge's division
/// region: where do each one's title and toolbar items go?
private struct ProbeTwoPane: View {
    var body: some View {
        GeometryReader { proxy in
            let division = proxy.reservedRegions(kind: .division, options: .includeInactive, layoutDirectionBehavior: .fixed).first?.frame
            let leading = division?.minX ?? proxy.size.width / 2
            let trailingStart = division?.maxX ?? proxy.size.width / 2
            HStack(spacing: 0) {
                NavigationStack {
                    ProbeReadout(title: "Left")
                        .toolbar { Button("Filter", systemImage: "line.3.horizontal.decrease") {} }
                }
                .frame(width: leading)
                Color.red.opacity(0.3).frame(width: trailingStart - leading)
                NavigationStack {
                    ProbeReadout(title: "Right")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) { Button("Back", systemImage: "chevron.backward") {} }
                            ToolbarItem { Button("More", systemImage: "ellipsis") {} }
                        }
                }
            }
        }
    }
}

/// D4: a cover filling the display, under the camera column.
private struct ProbeCover: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.indigo, .teal, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    VStack(spacing: 12) {
                        Text("PRIDE AND\nPREJUDICE").font(.largeTitle.bold()).multilineTextAlignment(.center)
                        Text("Jane Austen").font(.title2)
                    }
                    .foregroundStyle(.white)
                }
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Chapter 12 · 34%").font(.headline)
                        Text("Synced 2 min ago").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open") {}.buttonStyle(.glassProminent)
                }
                ProgressView(value: 0.34)
            }
            .padding()
            .glassEffect(in: .rect(cornerRadius: 24))
            .padding()
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}

/// D7: a page with the reader's controls in the toolbar.
private struct ProbeReader: View {
    @AppStorage("probeHideTabs") private var hideTabs = false

    var body: some View {
        ScrollView {
            Text(String(repeating: "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife. ", count: 20))
                .font(.system(.body, design: .serif))
                .padding()
        }
        .background(Color(red: 0.98, green: 0.95, blue: 0.88))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Back", systemImage: "chevron.backward") {} }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Contents", systemImage: "list.bullet") {}
                Button("Text and theme", systemImage: "textformat.size") {}
                Button("Search in book", systemImage: "magnifyingglass") {}
                Button("Bookmark", systemImage: "bookmark") {}
            }
            ToolbarItem(placement: .bottomBar) {
                Text("Chapter 12 · page 4 of 18").font(.caption)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbarVisibility(hideTabs ? .hidden : .automatic, for: .tabBar)
    }
}

private struct ProbeSearch: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ProbeReadout(title: "Search")
        }
        .searchable(text: $query, prompt: "Title, author, series")
    }
}

/// Prints what the layout sees: size, safe area, hinge, regions.
private struct ProbeReadout: View {
    let title: String
    @State private var posture = "–"
    @State private var geometry = "–"

    var body: some View {
        List {
            Section("Posture") { Text(posture) }
            Section("Geometry") { Text(geometry).font(.caption.monospaced()) }
            Section("Rows") {
                ForEach(1..<12) { Text("Row \($0)") }
            }
        }
        .navigationTitle(title)
        .onHingeChange { _, new in
            posture = new.hinge.map { "\($0.status) \(Int($0.angle.degrees))°" } ?? "no hinge"
        }
        .onGeometryChange(for: String.self) { proxy in
            let s = proxy.size, i = proxy.safeAreaInsets
            let regions = proxy.reservedRegions(kind: .division, options: .includeInactive, layoutDirectionBehavior: .fixed)
                .map { "division x\(Int($0.frame.minX)) w\(Int($0.frame.width)) \($0.isActive ? "active" : "inactive")" }
            let occlusions = proxy.reservedRegions(kind: .occlusion, options: .includeInactive, layoutDirectionBehavior: .fixed)
                .map { "occlusion \(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))×\(Int($0.frame.height))" }
            return (["size \(Int(s.width))×\(Int(s.height))",
                     "safe t\(Int(i.top)) l\(Int(i.leading)) b\(Int(i.bottom)) r\(Int(i.trailing))"]
                    + regions + occlusions).joined(separator: "\n")
        } action: { geometry = $0 }
    }
}
#endif
