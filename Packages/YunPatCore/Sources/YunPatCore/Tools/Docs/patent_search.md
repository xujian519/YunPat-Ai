---
name: patent_search
description: 在 CNIPA、Google Patents、SooPAT 中检索专利文献，支持布尔检索式、IPC 分类号、日期过滤。
version: 1.0.0
author: YunPat-AI Team
---

# patent_search

## When to Use

- 用户要求"检索专利"、"查找相关专利"、"搜索现有技术"
- 专利查新、FTO 检索、无效检索等业务场景的前置步骤
- 根据技术特征构建检索式后验证命中情况
- 对比不同数据源（CNIPA / Google Patents）的返回结果

## Typical Workflow

1. 从技术交底书或权利要求中提取核心检索要素（技术领域、技术问题、关键特征词）
2. 建议先以 IPC 分类号 + 少量关键词进行试探检索
3. 根据 `count` 评估命中量：过多则加限定词、缩窄日期区间；过少则检查同义词或放宽条件
4. 得到 50–200 条结果后，逐条阅读 `abstract` 筛选高相关专利
5. 对疑似高相关的专利，使用 `patent_download` 工具获取 PDF 原文精读

## Parameters

| Parameter   | Type   | Required | Default | Description                                          |
| ----------- | ------ | -------- | ------- | ---------------------------------------------------- |
| `query`     | string | yes      | —       | 检索式：支持布尔运算符（AND/OR/NOT）、括号、通配符   |

> ⚠️ 以下参数尚未实现（计划中）：
> - `source` (string, 默认 `all`) — 数据源：`cnipa` / `google` / `soopat` / `all`
> - `limit` (int, 默认 `20`) — 返回结果数量上限（1–100）
> - `date_from` (string) — 公开日起始，ISO 8601 格式
> - `date_to` (string) — 公开日截止，ISO 8601 格式
> - `category` (string) — IPC 分类号（如 `G06F40/279`）

## Return Value

成功 (`ok: true`)：

```json
{
  "ok": true,
  "data": {
    "query": "自然语言处理 AND G06F",
    "source": "all",
    "count": 47,
    "results": [
      {
        "rank": 1,
        "title": "一种基于深度学习的自然语言处理方法",
        "patent_number": "CN202310123456.7",
        "applicant": "中科院计算所",
        "abstract": "本发明提供一种...",
        "publication_date": "2024-03-15",
        "source": "google"
      }
    ]
  }
}
```

## Error Codes

| Code                  | 含义               | 处理建议                                       |
| --------------------- | ------------------ | ---------------------------------------------- |
| `INVALID_ARGS`        | `query` 为空或格式非法 | 检查 query 是否为非空字符串，布尔运算符是否成对 |
| `NO_RESULTS`          | 检索无匹配结果     | 去掉分类号限制、使用同义词、缩短日期区间重试   |
| `PROVIDER_UNAVAILABLE` | 指定数据源不可用   | 切换 source 到 `all`，等待后重试               |
| `NETWORK`             | 网络请求失败       | 重试一次；持续失败则 30 秒后重试，最多 3 次    |
| `TIMEOUT`             | 上游超时           | 缩小查询范围（加 IPC 分类号、缩短日期区间）后重试 |

## Tips

- **从宽到窄**：先用 `category` + 1–2 个关键词试探，结果超过 200 条时逐步加入 AND 限定、缩短日期区间
- **善用 IPC 分类号**：IPC 分类号精准锁定技术领域，比纯关键词检索召回率更可靠。先用关键词找到一篇相关专利，据此确定 IPC 分类号，再以分类号重新检索
- **零结果时换同义词**：先检查拼写和布尔运算符，然后尝试同义词/上下位概念（如"无人机"→"无人飞行器"、"深度学习"→"神经网络"）
- **多源交叉验证**：指定 `source: "all"` 可同时检索 CNIPA 和 Google Patents，避免单一数据源遗漏
- **日期过滤可大幅缩减结果集**：已知技术公开时间范围时务必使用 `date_from`/`date_to`

## Known Limitations

- 单次最多返回 100 条结果；超过该数量需分多页（调整 `limit` + 日期/分类号分批拉取）
- SooPAT 稳定性较低，指定 `source: "soopat"` 时可能频繁触发 `PROVIDER_UNAVAILABLE`
- 通配符和复杂布尔嵌套在不同数据源间行为不完全一致，建议对单一数据源使用其原生语法
