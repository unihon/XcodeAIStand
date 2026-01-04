#!/bin/bash

# Test MCP Server
# This script sends MCP JSON-RPC requests to test the server

echo "Testing MCP Server - Initialize"
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0.0"}}}' | .build/debug/XcodeAIStand -m

echo ""
echo "Testing MCP Server - List Tools"
echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | .build/debug/XcodeAIStand -m

echo "Testing get_project_structure..."
echo '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_project_structure","arguments":{}}}' | .build/debug/XcodeAIStand -mcp | head -n 20
echo "..."
echo ""

echo "Testing list_directory..."
echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_directory","arguments":{"path":"/Users/honlee/wk/XcodeAIStand/Sources"}}}' | .build/debug/XcodeAIStand -mcp | head -n 20
echo "..."
echo ""

echo ""
echo "Testing get_file_content..."
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_file_content","arguments":{"path":"/Users/honlee/wk/XcodeAIStand/README.md"}}}' | .build/debug/XcodeAIStand -mcp | head -n 20
echo "..."
echo ""

echo ""
echo "Testing MCP Server - Call Tool"
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_active_file_info","arguments":{}}}' | .build/debug/XcodeAIStand -m
