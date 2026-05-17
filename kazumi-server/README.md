# Kazumi Server

外部后备解析服务 - 仅在 Apple TV App 原生解析失败时获取最终视频 URL。

## 什么时候需要？

KazumiTV 默认使用 App 内原生解析和 `127.0.0.1` loopback 播放代理，不需要启动此服务。只有来源必须依赖真实浏览器执行复杂脚本、验证码或强反爬逻辑时，才需要显式启用外部后备解析。后备服务可以：

1. 执行完整的 JavaScript 来渲染页面
2. 使用无头浏览器 (Playwright) 抓取动态加载的视频
3. 代理规则仓库请求，作为网络受限时的后备通道

App 播放链路仍会回到 Apple TV 真机本地 `127.0.0.1` 代理；此服务不再是正常播放的必需组件。

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
2. 找到"外部解析服务"
3. 启用外部后备解析
4. 填写后备服务地址（如 `http://192.168.1.100:5001`，自定义端口时改为对应端口）
5. 点击"测试"确认连接

## 服务器地址

- 模拟器开发时：可以使用 `http://127.0.0.1:5001`
- 真机测试时：必须使用服务器电脑的局域网 IP（如 `http://192.168.1.100:5001`）
- 自定义端口时：把地址中的端口同步改成启动时指定的端口，例如 `http://192.168.1.100:6000`
- 公网：需要服务器有公网 IP 或使用内网穿透
