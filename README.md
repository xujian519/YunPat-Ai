# YunPat-Ai

面向专利代理人和专利律师的 macOS 桌面端 AI 智能体。

## 构建

```bash
git clone <repo>
cd YunPat-Ai
# 构建 SPM 包
cd Packages/YunPatNetworking && swift build && swift test
cd ../YunPatCore && swift build && swift test
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
  YunPatCore/          AgentLoop + CapabilityRegistry + ContextEngine
  YunPatNetworking/    多后端模型路由 (OpenAI/Anthropic/DeepSeek/GLM)
```

## 技术栈

- Swift 6 + SwiftUI + AppKit
- macOS 15.5+ / Apple Silicon
- SPM 包管理
- Keychain 凭证存储
