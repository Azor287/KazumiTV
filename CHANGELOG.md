# 更新日志

本项目遵循语义化版本号：`主版本.功能版本.修复版本`。

## v0.1.0 - 2026-05-08

KazumiTV 的首个公开开源版本。

### 新增

- Swift 与 SwiftUI 实现的 Apple TV/tvOS 客户端基础体验。
- 推荐、时间表、追番、历史、搜索、详情与播放等主要页面。
- 基于 Fuzi 的 XPath 插件解析能力。
- 使用 SQLite.swift 与 UserDefaults 的本地收藏、历史和设置存储。
- Python Flask + Playwright 服务器代理，用于在 tvOS 环境下解析播放地址。
- 设置页服务器代理配置与连接测试。
- 设置页版本信息，自动读取应用版本号与构建号。
- GitHub Actions CI，覆盖 tvOS 构建和 Python 代理服务检查。
- 开源项目基础文件：GPL-3.0 许可证、NOTICE、README、Issue 模板、PR 模板和 Dependabot 配置。

### 修复

- 改善设置页服务器地址输入框在 tvOS 聚焦状态下的文字可读性。
- 修复服务器地址输入时键盘被焦点变化自动关闭的问题。
- 避免文本框更新期间修改 SwiftUI 状态导致的运行时警告。

### 说明

- 本项目是 [Kazumi](https://github.com/Predidit/Kazumi) 的独立 Apple TV/tvOS 移植版本，已获得原作者同意，但并非由 Kazumi 原作者或原维护团队开发、维护或发布。
- KazumiTV 不托管、不分发、也不提供任何媒体内容。插件规则、数据源及相关网络请求均由用户自行配置和承担责任。
