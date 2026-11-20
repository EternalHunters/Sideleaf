import SwiftData
import SwiftUI

struct AIReviewSection: View {
    @Environment(AppState.self) private var app
    @Environment(AIReviewService.self) private var service
    @Environment(\.modelContext) private var context

    let memos: [Memo]

    @State private var showingSettings = false
    @State private var pending: PendingReview?
    @State private var actionError: String?

    private struct PendingReview: Identifiable {
        let id = UUID()
        let batch: AIReviewBatch
        let configuration: AIReviewConfiguration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Label("AI 回望", systemImage: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accentDeep)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 4)

                Button("模型设置") { showingSettings = true }
                    .buttonStyle(.borderless)
                    .disabled(service.isGenerating)

                Button(action: prepare) {
                    Text(service.isGenerating ? "生成中…" : "生成 AI 回望")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentDeep)
                .disabled(service.isGenerating)
            }

            if service.isGenerating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在整理记录")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
            }

            if let message = actionError ?? service.errorMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let report = service.report {
                reportContent(report)
            } else if !service.isGenerating {
                Text("从近 30 天的笔记里找文章素材，看看最近一周有哪些反复出现的线索。")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(17)
        .flomoCard()
        .sheet(isPresented: $showingSettings) {
            AIReviewSettingsView(configuration: service.configuration)
        }
        .sheet(item: $pending) { review in
            AIReviewConsentView(
                batch: review.batch,
                configuration: review.configuration,
                onConfirm: {
                    Task { await service.generate(batch: review.batch, configuration: review.configuration) }
                }
            )
        }
    }

    private func reportContent(_ report: AIReviewReport) -> some View {
        let byID = Dictionary(uniqueKeysWithValues: memos.map { ($0.id, $0) })

        return VStack(alignment: .leading, spacing: 11) {
            Text("\(report.periodLabel) · \(report.sourceCount) 条记录 · 生成于 \(DateText.absolute(report.generatedAt))")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSoft)

            sectionTitle("文章线索")
            if report.articleIdeas.isEmpty {
                emptyResult("这批记录还没有形成一组足够完整的文章素材。")
            }
            ForEach(Array(report.articleIdeas.enumerated()), id: \.offset) { _, idea in
                ideaCard(idea, sources: idea.memoIDs.compactMap { byID[$0] })
            }

            sectionTitle("近期观察")
                .padding(.top, 5)
            if report.observations.isEmpty {
                emptyResult("近 7 天暂未发现有多条记录支持的共同线索。")
            }
            ForEach(Array(report.observations.enumerated()), id: \.offset) { _, observation in
                observationCard(observation, sources: observation.memoIDs.compactMap { byID[$0] })
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private func emptyResult(_ message: String) -> some View {
        Text(message)
            .font(Theme.caption)
            .foregroundStyle(Theme.inkSoft)
    }

    private func ideaCard(_ idea: AIReviewReport.ArticleIdea, sources: [Memo]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(idea.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(idea.angle).font(Theme.body(13)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(idea.sections.enumerated()), id: \.offset) { index, section in
                    Text("\(index + 1). \(section.heading)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.ink)
                }
            }

            sourceLinks(sources, missing: idea.memoIDs.count - sources.count)

            Button {
                createDraft(idea, sources: sources)
            } label: {
                Label("生成 Markdown 草稿", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .tint(Theme.accentDeep)
            .disabled(sources.count != idea.memoIDs.count)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Theme.accentMist, in: RoundedRectangle(cornerRadius: 10))
    }

    private func observationCard(_ observation: AIReviewReport.Observation, sources: [Memo]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(observation.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(observation.detail)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if !observation.suggestion.isEmpty {
                Text(observation.suggestion)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.accentDeep)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sourceLinks(sources, missing: observation.memoIDs.count - sources.count)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10))
    }

    private func sourceLinks(_ sources: [Memo], missing: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(sources) { memo in
                Button {
                    app.openMemo(memo.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text(DateText.dayKeyString(memo.createdAt))
                            .monospacedDigit()
                        Text(memo.titleLine)
                            .lineLimit(1)
                    }
                    .font(Theme.caption)
                    .foregroundStyle(Theme.accentDeep)
                }
                .buttonStyle(.plain)
                .help("打开原记录")
            }
            if missing > 0 {
                Text("\(missing) 条原记录已删除，可重新生成回望。")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func prepare() {
        actionError = nil
        guard let configuration = service.configuration else {
            showingSettings = true
            return
        }
        let batch = AIReviewBatch.make(from: memos)
        guard batch.sources.count >= 2 else {
            actionError = AIReviewError.insufficientNotes.errorDescription
            return
        }
        pending = PendingReview(batch: batch, configuration: configuration)
    }

    private func createDraft(_ idea: AIReviewReport.ArticleIdea, sources: [Memo]) {
        guard sources.count >= 2, sources.count == idea.memoIDs.count else { return }
        do {
            let article = try Article.create(in: context, title: idea.title, markdown: idea.markdown(sources: sources))
            app.select(.articles)
            app.selectedArticleID = article.id
            app.showToast("已创建 Markdown 草稿")
        } catch {
            app.showToast("Markdown 草稿未能保存", icon: "exclamationmark.circle")
        }
    }
}

private struct AIReviewSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AIReviewService.self) private var service

    @State private var address: String
    @State private var model: String
    @State private var apiKey = ""
    @State private var error: String?

    init(configuration: AIReviewConfiguration?) {
        _address = State(initialValue: configuration?.endpoint.absoluteString ?? AIReviewConfiguration.defaultAddress)
        _model = State(initialValue: configuration?.model ?? AIReviewConfiguration.defaultModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("AI 回望 · 模型设置")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Text("填写支持 Chat Completions 和 JSON 输出的 OpenAI 兼容接口。")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSoft)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("接口地址")
                    TextField("接口地址", text: $address)
                        .labelsHidden()
                }
                GridRow {
                    Text("模型名称")
                    TextField("模型名称", text: $model)
                        .labelsHidden()
                }
                GridRow {
                    Text("API 密钥")
                    SecureField("API 密钥", text: $apiKey, prompt: Text("按接口要求填写"))
                        .labelsHidden()
                }
            }
            .textFieldStyle(.roundedBorder)

            Text("密钥保存在系统钥匙串。同一接口的密钥留空时沿用已保存的值。")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSoft)

            if let error {
                Text(error).font(Theme.caption).foregroundStyle(Theme.danger)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存设置", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentDeep)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 5)
        }
        .padding(22)
        .frame(width: 500)
        .background(Theme.card)
    }

    private func save() {
        do {
            try service.configure(address: address, model: model, newKey: apiKey)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct AIReviewConsentView: View {
    @Environment(\.dismiss) private var dismiss

    let batch: AIReviewBatch
    let configuration: AIReviewConfiguration
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("发送记录并生成 AI 回望")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Text("本次将发送 \(batch.periodLabel) 内 \(batch.sources.count) 条记录的日期与文本。")
                .font(Theme.body(13))

            Text(configuration.endpoint.absoluteString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.inkSoft)
                .textSelection(.enabled)

            if batch.hasExcerpts || batch.omittedCount > 0 {
                Text(coverageNote)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSoft)
            }

            Text("发送范围仅包含笔记文字和日期。")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSoft)

            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("发送并生成") {
                    dismiss()
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentDeep)
            }
            .padding(.top, 7)
        }
        .padding(22)
        .frame(width: 490)
        .background(Theme.card)
    }

    private var coverageNote: String {
        var notes: [String] = []
        if batch.hasExcerpts { notes.append("较长的记录仅发送开头") }
        if batch.omittedCount > 0 { notes.append("另外 \(batch.omittedCount) 条记录超出单次范围") }
        return notes.joined(separator: "，") + "。"
    }
}
