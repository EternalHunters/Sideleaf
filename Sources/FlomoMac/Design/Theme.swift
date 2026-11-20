import SwiftUI

/// flomo 桌面版的视觉基调：纸感、留白、低饱和的绿。
/// 桌面端面积更大，所以比手机版再收一点饱和度，避免大片绿色显得吵。
enum Theme {
    // MARK: 色板
    static let bg = Color(hex: 0xF7F6F2)
    static let sidebar = Color(hex: 0xF1EFE9)
    static let card = Color(hex: 0xFFFDF8)
    static let cardRaised = Color(hex: 0xFFFDFB)
    static let ink = Color(hex: 0x23211D)
    static let inkSoft = Color(hex: 0x7C776D)
    static let inkFaint = Color(hex: 0xAAA398)
    static let inkGhost = Color(hex: 0xC7C0B4)

    static let accent = Color(hex: 0x149C69)
    static let accentDeep = Color(hex: 0x0B7650)
    static let accentSoft = Color(hex: 0xE8F4ED)
    static let accentMist = Color(hex: 0xF1F8F4)
    static let glow = Color(hex: 0x30CF79)
    static let tag = Color(hex: 0x198B62)
    static let ai = Color(hex: 0x0E6548)
    static let danger = Color(hex: 0xA34242)
    static let dangerSoft = Color(hex: 0xF8ECEC)

    static let hairline = Color(hex: 0xE3E0D7)
    static let hairlineSoft = Color(hex: 0xECE9E1)
    static let field = Color(hex: 0xEDEAE3)
    static let fieldHover = Color(hex: 0xE7E4DC)

    // MARK: 尺寸
    static let cardRadius: CGFloat = 13
    static let pagePadding: CGFloat = 28
    static let sidebarWidth: CGFloat = 224
    static let listWidth: CGFloat = 356

    // MARK: 字体
    static func body(_ size: CGFloat = 15.5) -> Font {
        .system(size: size, weight: .regular)
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static let memoBody = Font.system(size: 15.5, weight: .regular)
    static let caption = Font.system(size: 12, weight: .regular)
    static let captionMedium = Font.system(size: 12, weight: .medium)
    static let sectionTitle = Font.system(size: 11.5, weight: .semibold)
    static let pageTitle = Font.system(size: 25, weight: .semibold)
    static let detailTitle = Font.system(size: 30, weight: .semibold)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

extension View {
    func flomoCard(radius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.hairlineSoft, lineWidth: 0.7)
            )
            .shadow(color: Color.black.opacity(0.025), radius: 12, y: 3)
    }

    func quietDivider() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.hairlineSoft)
                .frame(height: 0.7)
        }
    }
}

/// 点、线、格构成的品牌标记。和 App 图标同源：十六格里亮起一格。
struct FlomoMark: View {
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x1CB87C), Color(hex: 0x087449)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(size * 0.115), spacing: size * 0.055), count: 4),
                spacing: size * 0.055
            ) {
                ForEach(0..<16, id: \.self) { index in
                    Circle()
                        .fill(.white.opacity(index == 10 ? 0.98 : 0.28))
                        .frame(
                            width: index == 10 ? size * 0.145 : size * 0.105,
                            height: index == 10 ? size * 0.145 : size * 0.105
                        )
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.18), radius: 5, y: 2)
    }
}

struct PaperBackdrop: View {
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(
                colors: [Theme.accent.opacity(0.055), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 540
            )
            RadialGradient(
                colors: [Color.white.opacity(0.6), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}
