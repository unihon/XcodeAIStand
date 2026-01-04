# XcodeAIStand - Xcode AI Stand

[English](README.md)

让外部 AI Agent Client 与 Xcode 无缝集成。通过 MCP 协议实时同步编辑器状态，AI 可自动获取当前文件、光标位置、选中代码等上下文信息。

## 功能特性

- 获取当前Xcode编辑器的活动文件信息
- 支持光标位置、选中文本范围等详细信息
- 多种运行模式：MCP Stdio、MCP HTTP、直接文本输出

## 使用场景

AI 自动感知你在 Xcode 中的编辑状态，无需手动复制粘贴代码或指定上下文，直接提问即可：

- 分析下当前文件的逻辑
- 解释下选中的这段代码
- 这个方法的调用流程是什么
- 帮我优化这里的实现

![Claude Code](Statics/cc.jpg)

▲ iTerm2 Claude Code CLI with Xcode

## 使用方法

[XcodeAIStand 下载 ☘️](https://github.com/unihon/XcodeAIStand/releases)

### 权限要求
首次运行需要授予辅助功能（Accessibility）权限：

**系统设置** → **隐私与安全性** → **辅助功能**


###  Claude Code CLI
> 项目根目录/.mcp.json

```json 
{
  "mcpServers": {
    "XcodeAIStand": {
      "command": "your_XcodeStand_path"
    }
  }
}
```

###  Gemini ClI
> 项目根目录/.gemini/settings.json

```json 
{
  "mcpServers": {
    "XcodeAIStand": {
      "command": "your_XcodeStand_path"
    }
  }
}
```

## 其它实践
如果对话中AI没有调用XcodeStand，你可以在系统提示词中引导AI调用
> 系统提示词例子
```
当问题中包含以下关键词时，必须调用XcodeStand获取当前文件信息：
- 当前
- 选中
- 这里
- 光标
...
```

## 说明
### 命令行参数

| 参数 | 说明 |
|------|------|
| (无参数) | MCP Stdio 模式（默认） |
| `-http` | MCP HTTP 模式 |
| `-bind [host]:port` | 指定 HTTP 绑定地址（默认 :9000） |
| `-txt` | 直接文本输出模式，输出后退出 |
| `-snippet` | 包含代码片段（选中文本、前后上下文） |

### 运行模式

#### 1. MCP Stdio 模式（默认）

通过标准输入输出与 MCP 客户端通信：

```bash
XcodeAIStand
```

#### 2. MCP HTTP 模式

启动 HTTP 服务器，监听 MCP JSON-RPC 请求：

```bash
XcodeAIStand -http                      # 默认监听 :9000
XcodeAIStand -http -bind 127.0.0.1:9000 # 指定地址和端口
XcodeAIStand -http -bind :8080          # 仅指定端口
XcodeAIStand -http -snippet             # 包含代码片段
```

#### 3. 直接文本输出模式

一次性输出当前文件信息后退出：

```bash
XcodeAIStand -txt
```

### `-snippet` 参数说明

默认情况下，`get_project_current_active_file_info` 只返回精简信息：
- 文件路径
- 光标位置（行、列）
- 选中范围（起始行:列 - 结束行:列）

添加 `-snippet` 参数后，额外返回：
- 选中的文本内容
- 光标前的代码片段（100-200字符）
- 光标后的代码片段（100-200字符）

## MCP 接口

### Tools

| Tool 名称 | 描述 |
|-----------|------|
| `get_project_current_active_file_info` | 获取当前活动文件信息（文件路径、光标位置、选中代码） |
| `get_file_content` | 获取指定文件的完整内容 |
| `list_directory` | 递归列出目录下的文件（忽略隐藏文件和构建目录） |
| `get_project_structure` | 获取当前项目的文件结构 |

### Resources

| Resource URI | 描述 |
|--------------|------|
| `XcodeAIStand://project_current_active_file_info` | 当前活动文件信息资源 |

### MCP 请求示例

```bash
curl -X POST http://localhost:9000 \
     -H "Content-Type: application/json" \
     -d '{
       "jsonrpc": "2.0", 
       "id": 1, 
       "method": "tools/call", 
       "params": { 
         "name": "get_project_current_active_file_info" 
       }
     }'
```

## 输出示例

**精简模式（默认）:**
```
<PROJECT_CURRENT_ACTIVE_FILE_INFO>
The user's current state is as follows:
Active Document: /path/to/file.swift
Cursor: Line 42, Column 15
Selection Range: Line 10:5 - Line 12:20
</PROJECT_CURRENT_ACTIVE_FILE_INFO>
```

**完整模式（-snippet）:**
```
<PROJECT_CURRENT_ACTIVE_FILE_INFO>
The user's current state is as follows:
Active Document: /path/to/file.swift
Cursor: Line 42, Column 15
Selection Range: Line 10:5 - Line 12:20
Selected Text:
...
Previous Snippet:
...
Next Snippet:
...
</PROJECT_CURRENT_ACTIVE_FILE_INFO>
```

## 构建项目

```bash
# Debug 构建
swift build

# Release 构建（推荐，性能更好）
swift build -c release
```

编译产物输出路径：
- Debug: `.build/debug/XcodeAIStand`
- Release: `.build/release/XcodeAIStand`

---

<div align="center">
<a href='https://ko-fi.com/V7V61RL0IZ' target='_blank'><img height='36' src='https://storage.ko-fi.com/cdn/kofi3.png?v=6' alt='Buy Me a Coffee'></a>
</div>