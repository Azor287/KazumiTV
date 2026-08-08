# 规则实播矩阵与修复验证（2026-07-29）

## 结论

本轮对 KazumiRules `main` 分支现有的 21 条规则逐一执行了“搜索 → 详情/线路 → 媒体读取 → AVFoundation → AVPlayer 时间轴前进”的实时测试。

- 全线路通过：`TvTFun`、`xfdmneo`
- 至少一条线路可播：`baimao`、`DM84`、`fcdm`、`MXdm`
- 完全不可播：其余 15 条

初次全量测试执行 21 项，2 项通过、19 项失败，耗时 806.237 秒。修复后 `baimao` 从“0 条线路”恢复为 6 条线路，其中 1 条完成实际起播；另 5 条由第三方 CDN 返回 403/404 或动态网页兜底超时。

第二次完整矩阵在当前 LAX/代理出口下执行 21 项，1 项严格通过、20 项失败，耗时 833.9 秒。该轮大量站点同时出现连接重置、TLS 或证书链异常，因此它反映的是“当前出口下的实时状态”，不是客户端解析能力倒退。加入安全的瞬时网络重试后，`TvTFun` 定向复测重新达到 1/1 线路实际起播；`xfdmneo` 在第二次完整矩阵中保持 1/1 通过。

客户端已修复两类可控问题：

1. 支持 API 8 JSON 搜索与章节规则，解决 `TvTFun`、`sorani` 被当作空 XPath 规则的问题。
2. 当规则的绝对章节 XPath 因页面改版失效时，从限定的播放列表容器和播放页 URL 安全回退解析，解决 `baimao` 无线路的问题。
3. 规则下载增加 GitHub Raw 与 jsDelivr 回退，避免单一规则仓库入口的瞬时 TLS 故障造成假失败。
4. GET、HTML 和媒体清单读取增加最多 2 次的瞬时网络重试；超时、连接重置和握手中断可以恢复，但证书信任失败不会被绕过。
5. 搜索条目优先选择规范化后的精确标题匹配，减少同名剧场版或衍生条目造成的测试偏差。
6. WebKit 动态解析改用独立非主窗口承载，消除直接挂载到 SwiftUI 宿主视图的运行时警告。

默认规则已收紧为本轮全线路通过的 `TvTFun` 与 `xfdmneo`。另外补齐了与 Kazumi Apple 端相同的 Fetch/XHR 响应体探测，以支持 URL 不带 `.m3u8` 的 HLS 接口。TLS 证书、Cloudflare、当前公开播放页不再下发播放器以及第三方 CDN 的 403/404 不属于客户端可安全修复的问题，因此没有通过关闭证书校验或伪造测试结果来绕过。

## 测试范围

- 平台：tvOS 26.4 Simulator
- 应用：KazumiTV 0.2.0 build 4；规则解析修复为 build 5；WebView 响应体兼容补丁为 build 6；网络稳定性补丁交付为 build 7
- 时间：2026-07-29 19:17–21:04（Asia/Shanghai）
- 规则来源：`Predidit/KazumiRules` `main` 分支的实时 JSON，共 21 条
- 搜索词：`海贼王`
- 内容选择：优先标题匹配；若条目本身没有剧集，则在前 8 个搜索结果中继续寻找有播放线路的条目
- 剧集选择：每条解析出的播放线路取最后一集
- 通过标准：
  1. 搜索成功；
  2. 详情页解析出线路与剧集；
  3. 本机解析得到媒体地址；
  4. HLS playlist 或 MP4 byte range 可读取；
  5. AVFoundation 判定资源可播放；
  6. AVPlayer 最长等待 15 秒，时间轴必须大于 0。

测试不是只判断“拿到了 m3u8/mp4 URL”，而是要求 AVPlayer 实际起播。规则只要存在一条失败线路，严格 XCTest 就记为失败，并在报告中另外标记“部分可用”。

## 21 条规则结果

| 规则 | 搜索结果 | 解析线路 | 可播线路 | 状态 | 主要失败原因 |
|---|---:|---:|---:|---|---|
| TvTFun | 5 | 1 | 1 | 全部通过 | — |
| xfdmneo | 3 | 1 | 1 | 全部通过 | — |
| baimao（修复前） | 24 | 0 | 0 | 失败 | 绝对章节 XPath 随站点 DOM 改版失效 |
| baimao（修复后） | 24 | 6 | 1 | 部分可用 | 线路恢复；其余 CDN 返回 403/404 或网页兜底超时 |
| DM84 | 5 | 2 | 1 | 部分可用 | 第二条上游媒体不可用，网页兜底超时 |
| fcdm | 21 | 4 | 3 | 部分可用 | `v7.ppqrrs.com` 上游返回 HTTP 403 |
| MXdm | 12 | 4 | 2 | 部分可用 | 两条上游媒体分别返回 HTTP 403、404 |
| AGE | 24 | 8 | 0 | 失败 | 当前公开播放页只返回“不提供 PC 端播放”，未创建播放器或媒体请求 |
| 7sefun | 12 | 1 | 0 | 失败 | 跳转站触发 Cloudflare challenge |
| aafun | 12 | 1 | 0 | 失败 | 当前 `bbfun.cc` 播放器脚本未产生可用媒体 |
| dalvdm | 0 | 0 | 0 | 失败 | 搜索 HTTP 403 |
| enlie | 0 | 0 | 0 | 失败 | TLS 握手失败 |
| giriGiriLove | 0 | 0 | 0 | 失败 | 搜索结果为空 |
| gpjda | 0 | 0 | 0 | 失败 | 首页与搜索请求超时 |
| gugu3 | 10 | 2 | 0 | 失败 | 播放器相关地址无有效媒体，网页兜底超时 |
| mgnacg | 0 | 0 | 0 | 失败 | 搜索结果为空 |
| mutefun | 0 | 0 | 0 | 失败 | 搜索结果为空 |
| mwcy | 0 | 0 | 0 | 失败 | 搜索预热 HTTP 403 |
| omofun03 | 0 | 0 | 0 | 失败 | TLS 握手失败 |
| sorani | 19 | 1 | 0 | 失败 | API 8 解析成功，最终媒体域名 TLS 握手失败 |
| xfdm | 0 | 0 | 0 | 失败 | 源站 TLS 失败，搜索结果为空 |
| yishijie | 5 | 1 | 0 | 失败 | 播放器相关 URL 返回 404，网页兜底超时 |

## 原因分类

| 分类 | 规则 | 处理 |
|---|---|---|
| 客户端缺少 API 8 | TvTFun、sorani | 已实现 JSON 搜索、章节、变量和播放页模板 |
| 章节 XPath 失效 | baimao | 已增加限定播放列表容器的回退解析 |
| 部分 CDN 线路坏 | baimao、DM84、fcdm、MXdm | 保留可播线路；坏线路证据为实时 403/404 |
| 站点反爬/入口变化 | AGE、7sefun、dalvdm、mwcy | AGE 当前公开播放页没有媒体请求；其余不绕过 Cloudflare |
| TLS/证书 | enlie、omofun03、sorani、xfdm | 不关闭系统 TLS 校验 |
| 规则或源站无结果 | giriGiriLove、gpjda、mgnacg、mutefun | 需要上游规则或站点恢复 |
| 播放器脚本失配 | aafun、gugu3、yishijie | 静态解析和 WebKit 均未获得有效媒体 |

## 证据与复现

测试代码位于 `KazumiTVTests/AllRulesLiveMatrixTests.swift`。它默认跳过，避免第三方站点实时状态污染普通 CI。

在 tvOS Simulator 的测试进程中设置：

```text
KAZUMI_RUN_ALL_RULES_LIVE=1
```

可选搜索词：

```text
KAZUMI_RULE_TEST_KEYWORD=海贼王
```

初次 21 条全量测试的原始 XCTest 结果：

```text
/Users/alan/Library/Developer/Xcode/DerivedData/KazumiTV-bpmkqpmelspmdghcnyaiokyggisx/Logs/Test/Test-KazumiTV-2026.07.29_19-17-44-+0800.xcresult
```

`baimao` 修复后 6 条线路回归结果：

```text
/Users/alan/Library/Developer/Xcode/DerivedData/KazumiTV-bpmkqpmelspmdghcnyaiokyggisx/Logs/Test/Test-KazumiTV-2026.07.29_19-38-46-+0800.xcresult
```

补齐 Fetch/XHR 响应体探测后，AGE 8 条线路的定向复测结果：

```text
/Users/alan/Library/Developer/Xcode/DerivedData/KazumiTV-bpmkqpmelspmdghcnyaiokyggisx/Logs/Test/Test-KazumiTV-2026.07.29_20-11-34-+0800.xcresult
```

第二次 21 条完整矩阵（当前 LAX/代理出口）的原始结果：

```text
/Users/alan/Library/Developer/Xcode/DerivedData/KazumiTV-bpmkqpmelspmdghcnyaiokyggisx/Logs/Test/Test-KazumiTV-2026.07.29_20-41-09-+0800.xcresult
```

加入瞬时网络重试后，`TvTFun` 1/1 实际起播的定向结果：

```text
/Users/alan/Library/Developer/Xcode/DerivedData/KazumiTV-bpmkqpmelspmdghcnyaiokyggisx/Logs/Test/Test-KazumiTV-2026.07.29_21-02-57-+0800.xcresult
```

8 条线路仍全部未产生媒体候选。直接检查同一播放页也确认 HTML 仅包含站点提示，不包含播放器、iframe 或媒体入口。KazumiRules 的 AGE 规则自 2025-09-17 起只更新过域名，因此当前需要上游提供新的播放入口或规则；客户端不能从一个没有下发媒体请求的页面中恢复地址。AGE 已属于旧版预装清理名单，不会作为新安装的默认来源。

## 限制

- 这是“每条线路抽一个剧集”的实时抽样，不代表每部作品、每一集都已穷举。
- 第三方站点状态会随时间、地区、IP、证书和反爬策略变化；同一规则之后可能恢复或再次失效。
- 模拟器通过不等于所有 Apple TV 真机网络环境都通过。安装 IPA 后仍应在目标真机上复测至少一个默认来源。
