import SwiftUI
import SwiftData

struct ReviewDeckView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]
    @Query(sort: \DailyReview.day, order: .reverse) private var reviews: [DailyReview]
    @AppStorage("review.quota") private var quota = 5

    @State private var visibleMemoID: UUID?
    @FocusState private var reviewFocused: Bool

    private var record: DailyReview? {
        reviews.first { $0.dayKey == DateText.dayKeyString(.now) }
    }

    private var picked: [Memo] {
        let ids = record?.memoIDs ?? ReviewPlanner.pick(from: memos, count: quota, day: .now)
        let byID = Dictionary(uniqueKeysWithValues: memos.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    var body: some View {
        let cards = picked
        let currentIndex = cards.firstIndex(where: { $0.id == visibleMemoID }) ?? 0

        GeometryReader { geometry in
            VStack(spacing: 15) {
                header

                if cards.isEmpty {
                    WorkspaceEmptyState(title: "还没有可回顾的记录", icon: "book.closed")
                        .frame(height: cardHeight(available: geometry.size.height))
                } else {
                    HStack(spacing: 10) {
                        pageButton(forward: false, currentIndex: currentIndex, cards: cards)
                        pager(cards, currentID: cards[currentIndex].id)
                        pageButton(forward: true, currentIndex: currentIndex, cards: cards)
                    }
                    .frame(height: cardHeight(available: geometry.size.height))

                    footer(index: currentIndex, count: cards.count)
                }
            }
            .frame(maxWidth: 880)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PaperBackdrop())
        .focusable()
        .focusEffectDisabled()
        .focused($reviewFocused)
        .onKeyPress(.leftArrow) {
            move(by: -1, from: currentIndex, in: cards)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            move(by: 1, from: currentIndex, in: cards)
            return .handled
        }
        .onAppear {
            reviewFocused = true
            ensureToday()
        }
        .onChange(of: memos.count) { ensureToday() }
        .onChange(of: cards.map(\.id), initial: true) { _, ids in
            if let visibleMemoID, ids.contains(visibleMemoID) { return }
            visibleMemoID = ids.first
        }
    }

    private func cardHeight(available: CGFloat) -> CGFloat {
        min(510, max(0, available - 172))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("每日回顾")
                    .font(Theme.detailTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(DateText.startOfDay(.now).formatted(
                    .dateTime.month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))
                ))
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSoft)
            }

            Spacer()

            let streak = ReviewPlanner.streak(in: reviews)
            if streak > 0 {
                Label("连续回顾 \(streak) 天", systemImage: "flame")
                    .font(Theme.captionMedium)
                    .foregroundStyle(Theme.accentDeep)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Theme.accentSoft, in: Capsule())
            }
        }
        .padding(.horizontal, 55)
    }

    private func pager(_ cards: [Memo], currentID: UUID) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(cards, id: \.id) { memo in
                    memoryCard(memo)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 6)
                        .containerRelativeFrame(.horizontal)
                        .accessibilityHidden(memo.id != currentID)
                        .id(memo.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $visibleMemoID, anchor: .center)
        .accessibilityLabel("回顾卡片")
    }

    private func pageButton(forward: Bool, currentIndex: Int, cards: [Memo]) -> some View {
        let offset = forward ? 1 : -1
        let available = cards.indices.contains(currentIndex + offset)
        let label = forward ? "下一张" : "上一张"
        return Button {
            reviewFocused = true
            move(by: offset, from: currentIndex, in: cards)
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(available ? Theme.accentDeep : Theme.inkFaint)
                .frame(width: 40, height: 40)
                .background(available ? Theme.card : Theme.field.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .accessibilityLabel(label)
        .help(forward ? "下一张 →" : "上一张 ←")
    }

    private func move(by offset: Int, from currentIndex: Int, in cards: [Memo]) {
        let destination = currentIndex + offset
        guard cards.indices.contains(destination) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            visibleMemoID = cards[destination].id
        }
    }

    private func memoryCard(_ memo: Memo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text(DateText.ageLabel(memo.createdAt))
                    .font(Theme.captionMedium)
                    .foregroundStyle(Theme.accentDeep)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.accentSoft, in: Capsule())
                Text(DateText.full(memo.createdAt))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.bottom, 18)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    if !memo.text.isEmpty {
                        Text(TagParser.highlight(memo.text))
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.ink)
                            .lineSpacing(8)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !memo.imageDatas.isEmpty {
                        imageRow(memo.imageDatas)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
                .padding(.bottom, 16)
            }

            Divider()
            Button {
                app.select(.all)
                app.selectedMemoID = memo.id
            } label: {
                Label("打开原记录", systemImage: "arrow.up.right")
                    .font(Theme.captionMedium)
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 12)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .flomoCard(radius: 16)
    }

    private func imageRow(_ images: [Data]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(images.prefix(4).enumerated()), id: \.offset) { _, data in
                if let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func footer(index: Int, count: Int) -> some View {
        ZStack {
            Text("\(index + 1) / \(count)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.inkSoft)
                .accessibilityLabel("第 \(index + 1) 张，共 \(count) 张")

            HStack {
                Spacer()
                if record?.isCompleted == true {
                    Label("今日已完成", systemImage: "checkmark.seal.fill")
                        .font(Theme.captionMedium)
                        .foregroundStyle(Theme.accentDeep)
                } else if index == count - 1 {
                    Button {
                        complete()
                    } label: {
                        Label("完成今日回顾", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentDeep)
                }
            }
        }
        .frame(height: 34)
        .padding(.horizontal, 55)
    }

    private func ensureToday() {
        let day = Date.now
        let key = DateText.dayKeyString(day)
        let existing = (try? context.fetch(FetchDescriptor<DailyReview>())) ?? reviews
        guard !existing.contains(where: { $0.dayKey == key }) else { return }
        let ids = ReviewPlanner.pick(from: memos, count: quota, day: day)
        guard !ids.isEmpty else { return }
        let review = DailyReview(day: day, memoIDs: ids, quota: quota)
        context.insert(review)
        do {
            try context.save()
        } catch {
            context.delete(review)
            app.showToast("今日回顾未能保存", icon: "exclamationmark.circle")
        }
    }

    private func complete() {
        guard let record, !record.isCompleted else { return }
        record.completedAt = .now
        do {
            try context.save()
            app.showToast("今天读完了", icon: "checkmark.seal.fill")
        } catch {
            record.completedAt = nil
            app.showToast("回顾进度未能保存", icon: "exclamationmark.circle")
        }
    }
}
