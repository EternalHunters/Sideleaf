import SwiftUI

struct WorkspaceList<Filters: View, Rows: View>: View {
    let title: String
    let count: Int
    let emptyMessage: String
    let createAction: (label: String, run: () -> Void)?
    @ViewBuilder let filters: () -> Filters
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.pageTitle)
                        .foregroundStyle(Theme.ink)
                    Text("\(count) 项")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                if let createAction {
                    Button(action: createAction.run) {
                        Label(createAction.label, systemImage: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentDeep)
                    .controlSize(.extraLarge)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            filters()
                .padding(.horizontal, 20)

            Divider()

            if count == 0 {
                Text(emptyMessage)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) { rows() }
                        .padding(12)
                }
            }
        }
    }
}

struct WorkspaceRow<Content: View>: View {
    let selected: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(
                selected ? Theme.accentSoft : Theme.card,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Theme.accent.opacity(0.35) : Theme.hairlineSoft, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct WorkspaceEmptyState: View {
    let title: String
    let icon: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        }
        .foregroundStyle(Theme.inkSoft)
    }
}
