# Kazumi Server

服务器代理 - 用于在 Apple TV (tvOS) 上获取视频 URL。

## 为什么需要服务器？

tvOS 不支持 WKWebView 和 JavaScriptCore 的 DOM 操作，无法直接抓取网页视频。服务器代理可以：

1. 执行完整的 JavaScript 来渲染页面
2. 使用无头浏览器 (Playwright) 抓取动态加载的视频
3. 中转视频请求，绕过跨域限制

## 安装

```bash
cd kazumi-server
pip install -r requirements.txt
playwright install chromium
```

## 启动

```bash
./start.sh
```

脚本会自动：
- 检查并安装依赖
- 寻找可用端口（默认从 5000 开始）
- 显示启动的地址

## 停止

```bash
./stop.sh
```

## API

| 接口 | 说明 |
|------|------|
| `GET /health` | 健康检查 |
| `GET /scrape?url=xxx&plugin=age` | 抓取视频 URL |
| `GET /scrape_js?url=xxx` | 使用浏览器渲染抓取 |
| `GET /rules/index` | 代理 Kazumi 规则仓库索引 |
| `GET /rules/plugin?name=xxx` | 代理单条 Kazumi 规则 |

## 配置 Apple TV 应用

1. 打开应用设置
2. 找到"服务器代理"
3. 启用代理
4. 填写服务器地址（如 `http://192.168.1.100:5001`）
5. 点击"测试"确认连接

## 服务器地址

- 模拟器开发时：可以使用 `http://127.0.0.1:5001`
- 真机测试时：必须使用服务器电脑的局域网 IP（如 `http://192.168.1.100:5001`）
- 公网：需要服务器有公网 IP 或使用内网穿透
