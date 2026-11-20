import SwiftUI

struct DetailColumn: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            switch app.selection {
            case .all, .pinned, .tag:
                MemoDetailView()
            case .review:
                EmptyView()
            case .insights:
                InsightDetailView()
            case .articles:
                ArticleDetailView()
            case .todos:
                TodoDetailView()
            case .settings:
                SettingsDetailView()
            }
        }
        .background(PaperBackdrop())
    }
}
