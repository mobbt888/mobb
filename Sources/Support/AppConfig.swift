import Foundation

/// 应用集中配置项：站点地址、域名白名单、行为开关。
///
/// 换站只需要改这里，业务代码不用动。
enum AppConfig {

    /// 云手机站首页。该站是 hash 路由的 SPA（实际地址会落到 `.../#/`）。
    static let rootURL = URL(string: "https://h.js123.com.cn/#/")!

    /// 允许在 App 内 WebView 直接打开的主域。其余域名一律交给 Safari。
    static let allowedHosts: Set<String> = ["h.js123.com.cn"]

    /// 回前台后判定会话已过期、需要重新拉起页面的阈值（秒）。
    static let staleInterval: TimeInterval = 600

    /// 首屏看门狗超时（秒）：冷启动超过此时长仍未渲染成功就自动重载。
    static let firstLoadTimeout: TimeInterval = 8

    /// 首屏自动重试上限，避免站点真挂了时无限重载。
    static let maxFirstLoadRetries = 2

    /// 是否允许 JS 打开的新窗口在 App 内承接（false = 交给系统浏览器）。
    static let opensExternalInSafari = true

    /// 追加在 UA 后面的应用标识，便于服务端识别端来源。
    static let applicationNameForUserAgent = "CloudPhone/1.0"

    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https",
              let host = url.host?.lowercased() else { return false }
        return allowedHosts.contains(host) || allowedHosts.contains { host.hasSuffix(".\($0)") }
    }
}
