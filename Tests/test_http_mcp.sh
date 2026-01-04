#!/bin/bash

# Test HTTP MCP Server
# This script sends MCP JSON-RPC requests via HTTP POST

PORT=9000
URL="http://localhost:$PORT"

echo "Starting server in background..."
# Kill any existing server on this port
lsof -ti :$PORT | xargs kill -9 2>/dev/null
.build/debug/XcodeAIStand -mcp -b :$PORT &
SERVER_PID=$!
sleep 2

echo "Testing GET Request (Should be 405 Method Not Allowed)..."
curl -s -i "$URL" | head -n 5
echo ""

echo "Testing MCP Initialize (POST)..."
curl -s -X POST "$URL" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0.0"}}}' \
     | head -n 20
echo ""

echo "Testing MCP List Tools (POST)..."
curl -s -X POST "$URL" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
     | head -n 20
echo ""

echo "Testing MCP Call Tool (POST)..."
curl -s -X POST "$URL" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_active_file_info"}}' \
     | head -n 20
echo ""

# Cleanup
echo "Stopping server..."
kill $SERVER_PID
