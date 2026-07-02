---
name: patent_draft_claims
description: Draft patent claims from a technical disclosure, using the characterized-by (其特征在于) delimitation format. Produces an independent claim and dependent claims compliant with Article 26.4 of the Chinese Patent Law.
version: 1.0.0
author: YunPat-AI Team
---

# patent_draft_claims

## When to Use

- A technical disclosure (交底书) has been provided and claims need to be drafted
- The user asks to "write claims", "起草权利要求", or "撰写权利要求"
- An existing claim set needs revision based on updated technical features
- Preparing a patent application where claims are the first deliverable

## Typical Workflow

1. Read the technical disclosure to extract essential technical features.
2. Identify the closest prior art to determine the preamble (前序部分) vs. characterizing portion (特征部分).
3. Draft Claim 1 as an independent claim with preamble + "其特征在于" + characterizing features.
4. Draft dependent claims 2–N, each adding one distinct technical feature.
5. Verify with FactMarker that all features in the claims appear in the disclosure.
6. Run TabooDetector to check for prohibited terms.
7. Present the claim set with a brief explanation of the inventive concept.

## Parameters

| Parameter           | Type   | Required | Default | Description                                    |
| ------------------- | ------ | -------- | ------- | ---------------------------------------------- |
| `technical_solution`| string | yes      | —       | Full text of the technical disclosure          |
| `query`             | string | no       | —       | Alias for `technical_solution`                 |

## Return Value

The tool returns the technical solution text and instructs the LLM to generate claims. The actual claim text is produced by the LLM in the subsequent message.

## Error Codes

| Code           | Meaning                          | Recovery                                    |
| -------------- | -------------------------------- | ------------------------------------------- |
| `INVALID_ARGS` | No technical solution provided   | Provide `technical_solution` or `query`     |

## Tips

- Claim 1 should use the two-part form (前序+特征) only when the closest prior art is known. For pioneering inventions without clear prior art, use one-part form.
- Each dependent claim should add ONE technical feature. Avoid multi-feature dependent claims unless they represent a cohesive embodiment.
- Cite statutory basis: "符合专利法第26条第4款" (clear and supported by description).
- For software/algorithm patents, draft method claims first, then corresponding apparatus claims.
- Include fallback positions: broader independent claim + narrower dependent claims that capture specific embodiments.

## Known Limitations

- This tool triggers LLM-based drafting. The quality depends on the underlying model's patent law knowledge.
- The tool does not automatically check for unity of invention (单一性) across multiple independent claims.
- Chemical/biotech claims with Markush groups or sequence listings require manual expert review.
