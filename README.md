# YunPat-Ai

面向专利代理人和专利律师的 macOS 桌面端 AI 智能体。

## 构建

```bash
git clone <repo>
cd YunPat-Ai

# 快速开发（Makefile）
make build        # 构建所有包与 App
make test         # 运行全量测试

# 分步构建（SPM）
swift build --package-path Packages/YunPatNetworking
swift test  --package-path Packages/YunPatNetworking

swift build --package-path Packages/YunPatCore
swift test  --package-path Packages/YunPatCore

# 构建 App bundle
bash scripts/package-app.sh     # 产出 .build/YunPatAi.app
```

## 配置

1. 运行 App
2. 打开 Settings (⌘,)
3. 填入至少一个 API Key（DeepSeek 推荐，API 便宜速度快）
4. 返回主界面开始对话

## 架构

```
App/                  SwiftUI macOS App
  Views/               Chat UI 组件
Packages/
  YunPatCore/          AgentLoop + 知识库 + 记忆 + 专利引擎 + 隐私过滤 + 桌面工具
  YunPatNetworking/    多后端模型路由 (OpenAI/Anthropic/DeepSeek/GLM)
  PatentClient/        Google Patents + PSS 专利检索客户端
  YunPatPlugins/       插件系统 + MCP 协议 (ClaimDrafting/Infringement 等)
  YunPatDesktop/       桌面自动化 (AppleScript/AXorcist/Shell)
  YunPatSandbox/       沙箱 Provider
```

## 技术栈

- Swift 6 + SwiftUI + AppKit
- macOS 15.5+ / Apple Silicon
- SPM 包管理
- Keychain 凭证存储
