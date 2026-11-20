enum AppBrand {
    static let name = "Sideleaf"
    static let captureTitle = "\(name) 快速记录"
    static let urlScheme = "sideleaf"

    static func acceptsURLScheme(_ scheme: String?) -> Bool {
        [urlScheme, "nianye", "flomo-mac"].contains(scheme?.lowercased() ?? "")
    }
}
