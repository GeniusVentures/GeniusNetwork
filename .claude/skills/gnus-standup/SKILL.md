---
name: gnus-standup
description: Generate daily engineering standup with human and AI contributions.
disable-model-invocation: true
---

Generate today's standup from Git, GSD and LLM session history.
Return Markdown in a single fenced text block.

## [Project / Module] — YYYY-MM-DD
- Completed:
- Human contributions:
- AI contributions:
- Active human hours:
- AI execution hours (including unattended):
- Concurrent projects:
- Delivery and verification:
- Next / blockers:

Limit each project to 150 words. Consolidate related tasks.
Omit routine operations, technical minutiae, file inventories
and promotional language. Distinguish planning from implementation
and local work from delivered functionality.

Report measured, self-reported or estimated hours explicitly.
Never invent contribution percentages or double-count time.

Include a brief daily total when multiple projects are involved.

Report human hours as measured, self-reported or estimated.
Include the evidence supporting the estimate. Do not default
to an eight-hour workday. Quantify AI execution and unattended
time separately. Attribute architectural decisions to the
person who made them.