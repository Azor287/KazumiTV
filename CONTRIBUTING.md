# 贡献指南

感谢你愿意参与 KazumiTV。

KazumiTV 是 [Kazumi](https://github.com/Predidit/Kazumi) 的独立 Apple TV/tvOS 移植版本。本项目与原 Kazumi 并非同一作者或维护团队，请在提交 issue、PR 或对外介绍时避免造成混淆。

## 开发流程

请优先通过 Pull Request 提交改动：

1. 从 `main` 创建短期分支，例如 `feature/player-controls` 或 `fix/playback-timeout`。
2. 保持改动聚焦，避免把无关重构混在同一个 PR。
3. 提交前运行基础检查。
4. 在 PR 中说明改动内容、测试方式和已知风险。

## 本地构建

生成 Xcode 项目：

```bash
xcodegen generate
```

构建 tvOS Simulator Debug 版本：

```bash
xcodebuild -project KazumiTV.xcodeproj \
  -scheme KazumiTV \
  -configuration Debug \
  -destination 'generic/platform=tvOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

编译 App 与测试目标：

```bash
xcodebuild -project KazumiTV.xcodeproj \
  -scheme KazumiTV \
  -configuration Debug \
  -destination 'generic/platform=tvOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

## 贡献范围

欢迎提交：

- tvOS 交互和焦点体验优化
- Swift/SwiftUI 架构改进
- 播放器、弹幕、收藏、历史等功能修复
- 本机解析与 loopback 播放链路改进
- 文档、构建脚本、CI 改进

请不要提交：

- 侵权内容、内置片源、账号凭据或私有 API token
- 绕过付费、登录或访问控制的代码
- 与本项目目标无关的大规模重构

## 插件和内容声明

KazumiTV 不托管、不分发、也不提供任何媒体内容。用户需要自行确保其插件规则、数据源和使用方式符合所在地法律法规及相关服务条款。
