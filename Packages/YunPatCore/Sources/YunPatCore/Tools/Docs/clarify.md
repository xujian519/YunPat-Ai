---
name: clarify
description: Pause the agent loop and ask the user a blocking question. Provide optional choices to constrain the response. Use only for genuinely blocking ambiguity — make reasonable defaults for minor uncertainties.
version: 1.0.0
author: YunPat-AI Team
---

# clarify

## When to Use

- The technical disclosure is ambiguous on a critical feature needed to draft valid claims
- Multiple legal interpretations are possible and the choice materially affects the OA strategy
- The user's request is underspecified (e.g., "analyze this patent" without specifying novelty vs. infringement)
- The user's instruction contradicts known patent law and needs clarification

## Typical Workflow

1. Detect a genuine ambiguity that prevents forward progress.
2. Frame the question clearly in the user's language. Include context so they don't need to re-read the whole conversation.
3. Provide 2–5 concrete options. The first option should be your recommended default.
4. Wait for the user's response — the Loop pauses until answered.

## Parameters

| Parameter       | Type     | Required | Default | Description                                          |
| --------------- | -------- | -------- | ------- | ---------------------------------------------------- |
| `question`      | string   | yes      | —       | The clarifying question, in natural language         |
| `options`       | string[] | no       | `[]`    | Predefined choices (max 6). Leave empty for free-text |
| `allow_multiple`| bool     | no       | `false` | Whether the user can select multiple options         |

## Return Value

Success:

The user sees an overlay in the Chat UI with the question and options. Their response is inserted into the conversation context.

## Error Codes

| Code           | Meaning                   | Recovery                        |
| -------------- | ------------------------- | ------------------------------- |
| `INVALID_ARGS` | `question` is empty       | Provide a non-empty question    |

## Tips

- **Don't overuse this tool.** If the issue is minor, make a reasonable assumption and state it explicitly: "假设所述连接为螺栓连接，如需调整请告知。"
- Write options as complete sentences, not single words. "权利要求保护范围应覆盖所述方法及执行该方法的装置" beats "装置".
- The first option should be your recommendation so the user can just type "1" to proceed quickly.
- Never ask "continue?" — use `complete` when done. `clarify` is for directional choices.

## Known Limitations

- The Loop pauses at the `clarify` call and does not process any other work until the user responds.
- `options` are capped at 6 entries to avoid overwhelming the user.
