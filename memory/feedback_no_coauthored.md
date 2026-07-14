---
name: feedback-no-coauthored
description: Never add Co-Authored-By to commit messages — all commits must be authored solely by the user.
metadata:
  type: feedback
---

Never append `Co-Authored-By: Claude ...` or any Co-Authored-By trailer to commit messages.

**Why:** User explicitly requires all commits to be authored solely by them. The built-in Claude default adds this trailer automatically — it must be suppressed in this project.

**How to apply:** Every commit message ends after the user-facing text. No trailers, no co-author lines. Applies to all sub-projects (loyalty, operations, smartpedidos, cloud).
