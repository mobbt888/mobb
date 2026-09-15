# 云手机 iOS 封装壳

把 `https://h.js123.com.cn/`（云手机 Web 控制台）封装成 iOS App 的最小可用工程骨架，SwiftUI + WKWebView，遵循 Apple HIG（安全区、深色模式、动态字体、44pt 触控目标）。

## 关于原始资料

尝试访问 `https://h.js123.com.cn/封装API` 的结果是 **404**：

```
<Code>NoSuchKey</Code>
<Key>封装API</Key>
HostId: dfjsy.oss-cn-hangzhou.aliyuncs.com
```

该域名是阿里云 OSS 静态托管 + hash 路由的 SPA（实际会落到 `https://h.js123.com.cn/#/`），渲染后页面只有一个「新增云手机」入口，**没有获取到任何 HTTP API 文档**。因此本工程只做「Web 容器封装」，不含虚构的接口调用层。如果在别处有真实的服务端接口文档，把它贴进来，可以在 `Sources/Web/WebViewModel.swift` 之外新增 `Sources/API/` 一层对接。

## 目录结构

```
ios_cloudphone/
├─ project.yml                    // XcodeGen 工程描述（Bundle ID、签名、Info.plist 键值）
├─ ExportOptions.template.plist   // 导出选项模板
├─ Scripts/build_ipa.sh           // 一键打包脚本
├─ Resources/
│  ├─ Assets.xcassets/AppIcon.appiconset/   // 放图标 png
│  └─ CloudPhone.entitlements
└─ Sources/
   ├─ App/CloudPhoneApp.swift        // @main 入口 + 前后台刷新策略
   ├─ Support/AppConfig.swift        // 站点地址、域名白名单、行为开关（换站只改这里）
   ├─ Web/WebViewModel.swift         // WKWebView 创建、导航策略、进度、错误
   ├─ Web/RepresentedWebView.swift   // UIViewRepresentable 桥接
   ├─ UI/RootView.swift              // 主页：进度条 / 返回按钮 / 错误重试
   └─ API/APIClient.swift + TokenStore.swift
```

## 打包 .ipa

**硬限制：Windows 编译不了 iOS 应用。** .ipa 一定得在 macOS（本机 Mac、黑苹果、云 Mac、或 GitHub Actions 的 macos runner）上产出。本机是 Windows，所以这里交付的是「一跑就能出包」的工程描述与脚本，`project.pbxproj` 由 XcodeGen 现场生成，避免手写工程文件。

### 方案 A：未签名包（推荐，你自己重签）

不需要 Apple 开发者账号，也不需要证书：

```bash
brew install xcodegen
perl -pi -e 's/\r\n/\n/g' Scripts/build_ipa.sh   # 文件在 Windows 编辑过会是 CRLF，bash 会因 \r 报错
bash Scripts/build_ipa.sh unsigned
```

产物：`build/CloudPhone-unsigned.ipa`，即标准 `Payload/CloudPhone.app` 结构，**没有任何签名**，拿去用自己的证书或第三方工具签。

想用别的 Bundle ID：

```bash
PRODUCT_BUNDLE_IDENTIFIER=com.yourcompany.app bash Scripts/build_ipa.sh unsigned
```

### 方案 B：Xcode 直接签名

需要开发者账号并已在 Xcode ▸ Settings ▸ Accounts 登录：

```bash
DEVELOPMENT_TEAM=ABCDE12345 bash Scripts/build_ipa.sh development   # 真机调试（设备需登记 UDID）
DEVELOPMENT_TEAM=ABCDE12345 bash Scripts/build_ipa.sh ad-hoc        # 内测分发（≤100 台）
DEVELOPMENT_TEAM=ABCDE12345 bash Scripts/build_ipa.sh app-store     # 上架 / TestFlight
```

产物：`build/ipa/*.ipa`。团队 ID 在 https://developer.apple.com/account 的 Membership 页查。

### 没有 Mac？用 GitHub Actions 白嫖出包

仓库里已带 `.github/workflows/build-unsigned-ipa.yml`：

1. 把 `ios_cloudphone/` 整个目录推到一个 GitHub 仓库根目录；
2. Actions → **Build unsigned IPA** → Run workflow（可填 Bundle ID 和站点地址）；
3. 跑完在 Run 详情页底部 Artifacts 下载 `CloudPhone-unsigned-ipa`，解压就是 .ipa。

免费账号每月有额度，够用。

### 用你自己的证书重签

未签名 ipa 解出来后按你要的分发方式选一条：

**① 命令行（你有 p12 + mobileprovision）**

```bash
unzip CloudPhone-unsigned.ipa -d resign
# 描述文件放进去，名字必须是 embedded.mobileprovision
cp Your.mobileprovision resign/Payload/CloudPhone.app/embedded.mobileprovision
security import Your.p12 -P 证书密码 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
codesign -f -s "iPhone Developer: Your Name (TEAMID)" \
  --entitlements Resources/CloudPhone.entitlements \
  resign/Payload/CloudPhone.app
cd resign && zip -qry ../CloudPhone-signed.ipa Payload
```

企业证书（In-House）把 `-s` 换成 `iPhone Distribution: ...`，用 In-House 描述文件，即可免 UDID 直接分发。
个人/公司证书免 UDID 安装的活儿会被 Apple 封号，别干。

**② 图形工具（更省事）**：爱思助手、AltStore / SideStore、Sideloadly、ESign、轻松签——导入未签名 ipa + p12，一键签完直装。注意这些工具的在线签名服务有泄露证书风险，**优先用本地 p12 自签**。

无论哪种，Bundle ID 必须和描述文件里的 App ID 匹配（支持通配符 `com.xxx.*` 时前缀要对上），签名后请用 `codesign -vvv --deep Payload/CloudPhone.app` 验证。

### 上架前必须补的事

| 项 | 位置 | 说明 |
| --- | --- | --- |
| Bundle ID | `project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER` | 需在开发者后台注册 Identifiers；换包就换 ID，别和别人撞 |
| 团队 ID | `project.yml` 的 `DEVELOPMENT_TEAM` | 脚本也会按环境变量写回 |
| App 图标 | `Resources/Assets.xcassets/AppIcon.appiconset/` | 目录结构已放好，**png 要你自己补齐**：40/60/120/180 等各尺寸；缺 1024x1024 无法通过 App Store 校验 |
| 后台音频 | `Resources/CloudPhone.entitlements` | 需要息屏后保持云手机音频时，把 `UIBackgroundModes` 填 `audio` |
| 隐私清单 | Target ▸ Privacy | 用到相机/麦克风/相册时需在 App Store Connect 声明用途，否则审核被拒 |

### 审核风险（H5 壳的通病）

纯 WebView 壳容易被判 **Guideline 4.2 – Minimum Functionality**：一个和 Safari 打开没区别的网页 App，大概率被拒。降低风险的建议：在壳内加上 Safari 打开做不到的原生能力，例如推送通知（`UserNotifications`）、二维码扫码、人脸/指纹解锁进入、原生设置页（清晰度、帧率、退出登录）。原生 UI 建议连 `AppConfig.rootURL` 之外的功能一起做，而不是全塞进 WebView。

### Info.plist 关键项

已全部写进 `project.yml` 的 `info.properties`，改那里即可，Xcode 里不用再点：

| Key | Value | 说明 |
| --- | --- | --- |
| App Transport Security Settings ▸ Allow Arbitrary Loads | `NO` | 站点是全站 HTTPS，**不要**打开，保持系统默认更安全 |
| Privacy – Camera Usage Description | 按需 | 云手机里若调用扫码/拍照，须说明用途才能在真机通过审核 |
| Privacy – Microphone Usage Description | 按需 | 同上，语音输入场景需要 |
| Privacy – Photo Library Usage Description | 按需 | 截图保存场景需要 |
| Background Modes | `audio`（可选） | 需要后台保持云手机画面音频时勾选；不勾选也能正常运行 |
| Supported orientations | Portrait（建议） | 远程桌面类界面横竖屏混切易错乱 |

## 已经处理掉的封装坑

- **内联视频**：`allowsInlineMediaPlayback = true` + `mediaTypesRequiringUserActionForPlayback = []`，否则云手机画面会被系统全屏播放器接管或必须手动触发。
- **新窗口**：JS `window.open` / `target=_blank` 不再在壳内开孤儿页，统一交给系统 Safari，`Life-cycle` 干净且不会丢返回能力。
- **外部域名**：非白名单链接（`AppConfig.allowedHosts`）一律外跳，避免第三方登录页在壳内无法返回。
- **滑动返回**：`allowsBackForwardNavigationGestures = true`，网页级返回手势与系统一致。
- **会话保鲜**：进后台超过 `AppConfig.staleInterval`（默认 10 分钟）再回前台自动重载。
- **SDK（登录态）持久化**：使用默认 `WKWebsiteDataStore`，Cookie / localStorage 跨启动保留。
- **深色模式与动态字体**：全部使用语义色（`.systemBackground` / `.primary`）与系统文本样式，自动跟随系统设置。

## 换站

改 `Sources/Support/AppConfig.swift` 的 `rootURL` 与 `allowedHosts` 即可，其余代码无需改动。

## API 层在哪里

```
Sources/
├─ App/CloudPhoneApp.swift
├─ Support/AppConfig.swift         ← 站点地址、域名白名单
├─ Web/WebViewModel.swift          ← WebView 导航策略
├─ Web/RepresentedWebView.swift
├─ UI/RootView.swift
└─ API/
   ├─ APIClient.swift              ← 通用 HTTP 客户端（async/await + 重试 + 错误映射）
   └─ TokenStore.swift             ← Keychain 读写（token 别放 UserDefaults）
```

`APIClient` 现在是一个不含任何具体接口的通用客户端——因为原站点没提供 API 文档，不能凭空编接口字段。拿到文档后只需要：

```swift
let client = APIClient(baseURL: URL(string: "https://api.xxx.com")!) { TokenStore.token }
let devices: [Device] = try await client.request("/v1/devices", query: ["page": "1"])
try await client.send("/v1/devices/1/reboot", method: .post)
```

配套的 Model 用 `Codable` 结构体，字段名自动按 snake_case 转换（`keyDecodingStrategy = .convertFromSnakeCase`）。
