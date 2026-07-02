---
name: legal_status_query
description: 查询中国专利法律状态与事务记录 — 接入 CNIPA 公布公告系统，返回当前状态及事件时间线
version: 1.0.0
author: YunPat-AI Team
---

# legal_status_query

## When to Use

- 用户询问某件中国专利的"法律状态"、"是否授权"、"是否有效"
- 需要了解专利经历了哪些审查节点（实质审查生效、驳回、撤回等）
- 对方提供专利号后想快速判断该专利的当前实务状态
- 其他工具返回了专利号，需要进一步核实其法律效力

## Typical Workflow

1. 确认用户提供的专利号，补全国别前缀（如 `CN`）和校验位
2. 调用本工具，传入 `patent_number: "CN202410123456.7"`
3. 解析返回的 `data.status`（当前状态摘要）和 `data.events`（事务时间线）
4. 将状态转述给用户，必要时用事件列表支撑结论

## Parameters

| Parameter       | Type   | Required | Default | Description                              |
| --------------- | ------ | -------- | ------- | ---------------------------------------- |
| `patent_number` | string | yes      | —       | 完整的中国专利公开号，含 `CN` 前缀和校验位 |

## Return Value

Success (`ok: true`):

```json
{ "ok": true, "data": { "patent_number": "CN202410123456.7", "status": "授权", "events": [ { "date": "2024-06-15", "code": "B1", "description": "授权公告" } ] } }
```

Failure (`ok: false`):

```json
{ "ok": false, "error": { "code": "INVALID_ARGS", "message": "patent_number 必须包含 CN 前缀和校验位", "hint": "请提供完整公开号，如 CN202410123456.7" } }
```

## Error Codes

| Code                   | 含义                   | 处理建议                                         |
| ---------------------- | ---------------------- | ------------------------------------------------ |
| `INVALID_ARGS`         | 参数格式不正确         | 检查专利号是否包含 CN 前缀和完整校验位            |
| `NOT_FOUND`            | 指定的专利号不存在     | 核实申请号/公开号，确认该专利已公开               |
| `PROVIDER_UNAVAILABLE` | CNIPA 系统暂时不可达   | 稍等数分钟后重试，或使用 `cnipa-query` 技能直连  |
| `NETWORK`              | 网络请求失败           | 检查网络连通性与 CNIPA 服务可达性后重试           |

## Tips

- 务必使用完整的专利公开号，格式为 `CN` + 9 位数字 + `.` + 1 位校验位
- 法律状态存在 1–2 周的公示延迟，刚提交的申请可能查不到最新进展
- `status` 字段是当前状态的摘要，详细历史请查看 `events` 数组
- 若返回 `PROVIDER_UNAVAILABLE`，可引导用户去 epub.cnipa.gov.cn 手动核实

## Known Limitations

- 仅支持中国专利（CN 前缀），不支持 US/EP/WO 等其他司法辖区
- CNIPA 网站偶发 WAF 拦截，可能导致查询耗时 10–30 秒
- 数据刷新存在 1–2 周延迟，不适合查询刚发生的状态变更
