import SwiftUI

struct BrowserColumn: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            switch app.selection {
            case .all, .pinned, .tag:
                MemoBrowserView()
            case .review:
                EmptyView()
            case .insights:
                InsightBrowserView()
            case .articles:
                ArticleBrowserView()
            case .todos:
                TodoBrowserView()
            case .settings:
                SettingsBrowserView()
            }
        }
        .background(Theme.bg)
    }
}
