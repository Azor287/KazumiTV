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

默认端口为 `5001`。

如果需要自定义服务端口，可以传入 `--port` 或 `-p`：

```bash
./start.sh --port 6000
```

也可以同时指定监听地址：

```bash
./start.sh --host 0.0.0.0 --port 6000
```

如果只希望本机访问服务器，可以使用：

```bash
./start.sh --host 127.0.0.1 --port 6000
```

脚本启动时会先停止旧的 `api_server.py` 进程，然后将参数传递给 `api_server.py`。

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
4. 填写服务器地址（如 `http://192.168.1.100:5001`，自定义端口时改为对应端口）
5. 点击"测试"确认连接

## 服务器地址

- 模拟器开发时：可以使用 `http://127.0.0.1:5001`
- 真机测试时：必须使用服务器电脑的局域网 IP（如 `http://192.168.1.100:5001`）
- 自定义端口时：把地址中的端口同步改成启动时指定的端口，例如 `http://192.168.1.100:6000`
- 公网：需要服务器有公网 IP 或使用内网穿透
