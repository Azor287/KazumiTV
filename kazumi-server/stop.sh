#!/bin/bash
# 停止 Kazumi Server

echo "正在停止 Kazumi Server..."

# 结束该目录下的 server.py 进程
cd "$(dirname "$0")"

# 查找并结束进程
pkill -f "python.*kazumi-server/api_server.py" 2>/dev/null

sleep 1

# 检查是否还有进程
if pgrep -f "python.*kazumi-server/server.py" > /dev/null 2>&1; then
    echo "服务器仍在运行，强制结束..."
    pkill -9 -f "python.*kazumi-server/api_server.py"
fi

echo "服务器已停止"
