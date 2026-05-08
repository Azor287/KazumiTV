#!/bin/bash
# KazumiTV 服务器启动脚本

cd "$(dirname "$0")"

# 清理旧的 api_server 进程
pkill -f "api_server.py" 2>/dev/null
sleep 1

# 启动服务器
./venv/bin/python api_server.py
