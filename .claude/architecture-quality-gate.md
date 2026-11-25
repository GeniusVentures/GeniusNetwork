## Architecture Quality Gate

Apply these instructions to GeniusVentures, GNUS.ai, and related engineering projects using GSD.

Before executing any GSD phase, invoke the `architecture-review` skill for that phase. Use the shared skill installed from GeniusNetwork in the personal Claude Code skills directory, or the canonical GeniusNetwork copy when working in that repository. Do not require a separate skill file in each submodule. If the current shared skill is unavailable, stop and ask for installation rather than skipping the review.

- Inspect actual source code and dependencies.
- Reject unnecessary duplication, complexity, workarounds, and incorrect architectural boundaries, respecting established architecture and documented engineering decisions.
- Revise plans until all blocking findings are resolved.
- Never downgrade a blocker merely to proceed.
- Re-review when implementation plans materially change.
- Stop execution if the approved architecture proves invalid.
- Only the project owner may approve architectural exceptions.

Complete the independent review before executing the phase. Do not proceed on `CHANGES REQUIRED` or `REVIEW INCOMPLETE`. For GSD plan-checker reviews, honor the skill's native output contract and require `VERIFICATION PASSED` before execution. Preserve the evidence and reviewed revision in the existing GSD planning artifacts.
