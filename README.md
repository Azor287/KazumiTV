

# KazumiTV

> 注意：此项目与 [Kazumi](https://github.com/Predidit/Kazumi) 并非同一作者，为经过原作者同意开发的 Apple TV 移植版本。

KazumiTV 是 [Kazumi](https://github.com/Predidit/Kazumi) 的独立 Apple TV/tvOS 移植版本，使用 Swift 与 SwiftUI 重新实现。

本仓库与原 Kazumi 项目独立维护，并非由 Kazumi 原作者或原维护团队开发、维护或发布。本移植版本已获得原作者同意，原项目来源与归属信息同时记录在 [NOTICE](NOTICE) 中。

## 项目状态

KazumiTV 目前处于活跃开发阶段。应用面向 tvOS 平台，使用 `URLSession + Fuzi + JavaScriptCore` 与本机隐藏网页运行时解析视频地址，并在 App 内启动只绑定 `127.0.0.1` 的 loopback 播放代理，为 HLS 播放列表、分片、密钥和 MP4 请求注入必要请求头。安装和播放不需要部署额外服务。

## 使用截图

以下截图仅用于展示 KazumiTV 在 Apple TV 真机上的界面效果，截图中的媒体画面与海报版权归原权利方所有。

| 推荐页 | 详情页 | 播放器 |
| --- | --- | --- |
| ![KazumiTV 推荐页](docs/images/screenshot-home.jpeg) | ![KazumiTV 详情页](docs/images/screenshot-detail.jpeg) | ![KazumiTV 播放器](docs/images/screenshot-player.jpeg) |

## 架构

- tvOS 应用：Swift、SwiftUI、MVVM
- 导航：基于 `NavigationStack` 与共享 Router
- 插件解析：通过 Fuzi 进行 XPath 解析
- 视频解析：静态/轻量脚本使用原生解析，动态页面使用本机隐藏网页运行时
- 播放代理：App 内 `127.0.0.1` loopback HLS/MP4 代理，负责重写播放列表与透传 Range
- 本地存储：SQLite.swift 与 UserDefaults
- 图片加载与缓存：Kingfisher

## 环境要求

- Xcode 15 或更新版本
- tvOS 17.0 或更新版本
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## 构建

请确保在包含 `project.yml` 的项目根目录执行以下命令：

```bash
xcodegen generate
```

构建 Apple TV 模拟器版本：

```bash
xcodebuild -project KazumiTV.xcodeproj \
  -scheme KazumiTV \
  -configuration Debug \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Release 与 tvOS 侧载

正式发布包与更新说明请见 [GitHub Releases](https://github.com/Azor287/KazumiTV/releases)。版本号和构建号以 `project.yml` 中的 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION` 为准。

### 已签名 IPA

在已配置 Apple Developer tvOS 团队、证书和 Provisioning Profile 的环境中生成 Release 归档：

```bash
xcodegen generate
xcodebuild archive \
  -project KazumiTV.xcodeproj \
  -scheme KazumiTV \
  -configuration Release \
  -destination 'generic/platform=tvOS' \
  -archivePath build/KazumiTV.xcarchive
```

侧载 IPA 必须使用 Apple Developer tvOS 证书和 Provisioning Profile 签名，主 App `com.kazumi.tv` 与 Top Shelf 扩展 `com.kazumi.tv.topshelf` 都需要包含在签名配置中。可以在 Xcode Organizer 中从归档选择 **Distribute App** 导出 Development/Ad Hoc IPA。

也可以使用命令行导出。`ExportOptions.plist` 应使用自己的 Team ID、签名方式和两个 Bundle ID 对应的 Profile；不要把证书、Profile 或 Team ID 配置提交到仓库：

```bash
xcodebuild -exportArchive \
  -archivePath build/KazumiTV.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist /path/to/ExportOptions.plist
```

### 未签名 IPA（仅用于重签）

没有匹配的 Provisioning Profile 时，可以生成未签名归档并打包为重签输入。未签名 IPA 不能直接安装到 Apple TV：

```bash
xcodegen generate
xcodebuild archive \
  -project KazumiTV.xcodeproj \
  -scheme KazumiTV \
  -configuration Release \
  -destination 'generic/platform=tvOS' \
  -archivePath build/KazumiTV-unsigned.xcarchive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""

rm -rf build/Payload
mkdir -p build/Payload
cp -R build/KazumiTV-unsigned.xcarchive/Products/Applications/KazumiTV.app build/Payload/KazumiTV.app
ditto -c -k --norsrc --keepParent build/Payload build/KazumiTV-unsigned.ipa
rm -rf build/Payload
```

发布到 Release 前请确认 IPA 已签名，并在目标 Apple TV 上完成对应的开发者信任或侧载工具配置。

## 弹幕 API 配置

KazumiTV 按原版 Kazumi 的方式调用 DanDanPlay API。DanDanPlay 请求需要应用 ID 与密钥签名；源码构建时，请在本地配置自己的 DanDanPlay Open API 凭据。

复制模板文件：

```bash
cp Config/DanDanPlay.local.example.xcconfig Config/DanDanPlay.local.xcconfig
```

然后编辑 `Config/DanDanPlay.local.xcconfig`：

```xcconfig
DANDANPLAY_APP_ID = <your-app-id>
DANDANPLAY_APP_SECRET = <your-app-secret>
```

重新生成 Xcode 工程并构建：

```bash
xcodegen generate
xcodebuild -project KazumiTV.xcodeproj \
  -scheme KazumiTV \
  -configuration Debug \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

请不要把真实 DanDanPlay 密钥提交到仓库。`Config/DanDanPlay.local.xcconfig` 已被 Git 忽略；未配置凭据时，播放器会保留弹幕开关与渲染能力，但弹幕加载会显示未配置提示。

## 播放解析模式

播放链路完全在 Apple TV 本机完成：

```text
原生页面解析 -> 本机动态网页解析（按需） -> App 内 127.0.0.1 loopback 代理 -> AVPlayer
```

本地 loopback 代理只监听 Apple TV 真机自己的 `127.0.0.1` 随机端口，不会暴露到局域网。它会把远端 m3u8/mp4 映射为短 token URL，重写 HLS master/media playlist、segment、`EXT-X-KEY` 和 `EXT-X-MAP`，并透传 `Range`、`Content-Type`、`Content-Length`、`Content-Range` 等响应头。

动态网页解析默认开启，可以在设置中关闭。验证码、登录态或强反爬页面仍可能无法解析，应用会自动切换下一来源。

> 侧载说明：tvOS 没有公开可用的网页视图 API，动态网页解析因此通过运行时加载系统 WebKit 类实现，仅适用于自行签名/侧载构建，不能作为 App Store 审核兼容方案；系统升级后若该运行时不可用，原生解析来源仍可继续工作。

## 规则源

首次安装会优先尝试从 [KazumiRules](https://github.com/Predidit/KazumiRules) 获取端侧推荐规则 `TvTFun`、`xfdmneo`，并以内置 AGE、DM84、aafun 作为离线兜底。`TvTFun` 是本项目通过本机 API 8 解析保留的兼容规则，属于弃用标记的本地兼容例外；规则仓库中被标记为验证码或弃用的规则不会自动推荐。

规则管理页面会隐藏 `deprecated=true` 的已安装规则和规则仓库条目；普通安装、更新和导入流程也会拒绝弃用规则（`TvTFun` 的本地兼容例外除外）。已有安装不会在播放时自动联网更新规则；可以在“规则管理”里使用“安装推荐”或“规则仓库”手动安装其他端侧规则。

规则标签中，`本地`表示使用 App 本机解析能力（原生或轻量脚本；需要本机动态网页运行时的来源也可能显示此标签），`需验证`表示规则声明启用了验证码/反爬验证。默认播放源排序会优先使用近期开播成功的来源；没有历史记录时，会优先选择本机可解析且不需要浏览器运行时或验证的来源。

## 与 Kazumi 的关系

KazumiTV 是原 [Kazumi](https://github.com/Predidit/Kazumi) 项目的 Swift/tvOS 移植版本。请不要将本仓库与上游 Kazumi 项目混淆：

- 原项目：[Predidit/Kazumi](https://github.com/Predidit/Kazumi)
- KazumiTV：独立维护的 tvOS 移植版本
- 开发许可：本移植版本已获得原作者同意
- 作者关系：KazumiTV 与 Kazumi 不是同一项目，也不是由同一作者或团队维护

## 免责声明

KazumiTV 不托管、不分发、也不提供任何媒体内容。插件规则、数据源及相关网络请求均由用户自行配置和承担责任。用户必须遵守所在地法律法规，以及其所配置第三方来源的服务条款。

## 许可证

KazumiTV 使用 GNU General Public License version 3 授权，与原 Kazumi 项目使用的许可证保持一致。详见 [LICENSE](LICENSE)。

原 Kazumi 项目及其贡献者保留其在原项目中的相应权利。
