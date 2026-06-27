# 设计建议-chatgpt



我认真阅读了你的设计稿。

先给一个总体评价：

> **这不是一份普通的产品设计稿，而更像是一份可以指导未来 2~3 年开发工作的 Architecture RFC。**

尤其结合我们之前讨论过的目标（专利 Agent、知识图谱、7~8 万法律文档、PatentLoop、Karpathy Wiki、CNIPA 检索等），可以看出整体思想已经比较统一。

但是，如果站在**真正准备投入开发**的角度，我认为目前还有一些**架构层面的风险**，其中有几个我认为属于**必须在编码前调整**的问题。

------

# 我认为最大的优点

## 一、方向是正确的

我一直比较担心一个问题：

很多 AI Agent 项目，一开始就变成：

> ChatGPT + MCP + Tool Calling

最后就是一个聊天机器人。

而你的设计已经不是这个思路。

你的核心其实是：

```
Agent

↓

Loop

↓

Planner

↓

Rule Engine

↓

Memory

↓

Knowledge

↓

Tool
```

也就是说：

Tool 已经退居后面。

真正核心是：

Agent Loop。

这一点我认为非常正确。

------

## 二、PatentLoop 设计很好

尤其：

```
事实

↓

规则

↓

规划

↓

执行

↓

检查
```

这五步。

这是法律业务天然流程。

不是 LLM 发明出来的。

以后换模型：

GPT

Claude

DeepSeek

Gemini

甚至未来任何模型，

PatentLoop 都不用改。

这一点价值非常高。

------

## 三、知识库没有重新造轮子

这一点我特别赞同。

你已经有：

Karpathy Wiki

Obsidian

Embedding

Concept Index

Card

Semantic Index

完全没必要：

```
重新建立数据库

重新同步

重新导入
```

直接 Adapter。

这是最优解。

------

# 但是下面这些地方，我认为需要修改。

我按照重要程度排序。

------

# 第一（最重要）

## Tool Router 不应该成为整个系统中心

目前图里：

```
Loop

↓

ToolRouter

↓

所有能力
```

我建议：

改。

应该变成：

```
Loop

↓

Capability

↓

Tool
```

什么意思？

例如：

```
检索

↓

Search Capability

↓

CNIPA

Google Patent

Espacenet

Wiki

Embedding
```

而不是：

Loop

↓

Tool

↓

Search

原因：

未来 Tool 会越来越多。

可能：

500+

1000+

如果都是 ToolRouter：

LLM 每次：

listTools()

它会疯掉。

------

建议：

增加：

```
Capability Layer
```

例如：

```
Planning Capability

Reasoning Capability

Search Capability

Draft Capability

Review Capability

Desktop Capability
```

Capability 内部：

再调 Tool。

这样：

LLM 永远只知道：

几十个 Capability。

而不是：

几百个 Tool。

------

这是我认为整个架构最应该补的一层。

------

# 第二

## Agent Loop 不应该只有一个

目前：

```
AgentLoop

PatentLoop
```

我建议：

以后应该演化为：

```
Workflow

↓

Loop

↓

Skill

↓

Tool
```

例如：

以后：

```
PatentLoop

InfringementLoop

InvalidationLoop

SearchLoop

DraftLoop

ReviewLoop

OfficeActionLoop
```

不要全部写进 PatentLoop。

PatentLoop：

应该只是 Workflow。

Workflow：

调用很多 Loop。

例如：

```
PatentLoop

↓

SearchLoop

↓

ReasoningLoop

↓

DraftLoop

↓

ReviewLoop
```

这样以后扩展：

非常容易。

------

# 第三

## Memory 不应该只有三层

我建议至少：

五层。

例如：

```
Conversation

↓

Session

↓

Case

↓

Knowledge

↓

Global
```

为什么？

例如：

以后：

一个代理人

一年：

300 个案件。

他会形成：

自己的：

```
写作风格

检索习惯

OA 回复风格

创造性论证风格
```

这些：

不是 Case。

而是：

Global Memory。

否则：

Case 越来越大。

越来越难管理。

------

# 第四（非常重要）

## Rule 不应该只是 Retrieval

目前：

Rule：

就是：

Retrieve。

我建议：

增加：

Rule Engine。

例如：

```
Rule

↓

Normalize

↓

Conflict Resolve

↓

Priority

↓

Constraint

↓

Evidence
```

例如：

法律：

```
法

↓

司法解释

↓

审查指南

↓

案例

↓

复审决定
```

优先级不同。

应该：

Engine。

不是：

RAG。

------

# 第五

## Planner 应该独立

目前：

Planner：

在 PatentLoop。

建议：

独立 Package。

例如：

```
Planner

↓

Task Graph

↓

Dependency

↓

Priority

↓

Retry

↓

Checkpoint
```

未来：

所有 Agent：

都会用。

------

# 第六

## Context Builder

这个我之前一直建议。

现在设计稿还没有。

应该增加：

```
Prompt

×

Memory

×

Knowledge

×

Current Document

×

Workspace

×

User Preference

↓

Context Builder

↓

LLM
```

否则：

Prompt 会越来越大。

越来越乱。

Context Builder：

以后会成为：

整个 Agent 的核心。

------

# 第七

## Tool Schema 太简单

目前：

```
description

parameter

permission
```

建议增加：

```
cost

latency

confidence

cacheable

parallel

idempotent

side effect
```

例如：

CNIPA：

```
latency

4 秒
```

Embedding：

```
200ms
```

Planner：

可以自己调度。

------

# 第八

## Plugin

建议增加：

Capability Plugin。

而不是：

只有 Tool Plugin。

例如：

插件：

可以直接注册：

```
Search Capability

Draft Capability
```

而不是：

100 个 Tool。

------

# 第九

## Workflow Graph

目前：

Workflow：

写死。

建议：

以后：

全部：

Graph。

例如：

```
Step

↓

Node

↓

Edge

↓

Condition

↓

Retry

↓

Human
```

以后：

Workflow：

全部 YAML。

不用写 Swift。

例如：

```
PatentLoop.yaml

OA.yaml

Search.yaml

Invalidation.yaml
```

以后：

维护效率：

会高很多。

------

# 第十

## Model Router 建议升级

现在：

```
Provider

↓

Model
```

建议：

变成：

```
Capability

↓

Policy

↓

Provider

↓

Model
```

例如：

```
Reasoning

↓

Claude
Embedding

↓

bge
OCR

↓

Qwen OCR
```

以后：

真正实现：

Best Model。

而不是：

Best Provider。

------

# 我认为未来还应该增加三个核心模块

这是我觉得未来一定会出现的。

------

## ① Task Graph Engine

管理：

整个 Agent。

不是：

Loop。

而是：

DAG。

例如：

```
Search

↓

Extract

↓

Compare

↓

Write

↓

Review
```

------

## ② Context Engine

这是未来 Agent 最大竞争力。

负责：

上下文构建。

而不是 Prompt。

------

## ③ Evidence Engine

法律 Agent：

最大的特点：

不是回答。

而是：

每一句：

都有：

出处。

例如：

```
观点

↓

Rule

↓

Evidence

↓

Citation

↓

Confidence
```

以后：

整个 Reviewer：

都可以基于它。



这次重构会围绕五个新增的核心层展开：

1. **Capability Layer（能力层）**：让 LLM 面向能力而非大量工具。
2. **Context Engine（上下文引擎）**：统一构建模型输入，管理 Prompt、知识、记忆和工作区上下文。
3. **Task Graph Engine（任务图引擎）**：用 DAG 和可配置 Workflow 替代大量硬编码流程。
4. **Rule & Evidence Engine（规则与证据引擎）**：管理法律规则优先级、冲突解析和证据引用，而不仅仅是检索。
5. **Execution Runtime（执行运行时）**：统一调度 Loop、Capability、Tool、插件和模型，实现可观察、可恢复、可回放的执行过程。

我认为，这五层会比继续增加更多插件或功能，对整个系统的长期价值更大。