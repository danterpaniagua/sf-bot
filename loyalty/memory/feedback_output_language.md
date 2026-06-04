---
name: feedback-output-language
description: Language rules for all Claude output in this project
metadata:
  type: feedback
---

Always respond in English for all analysis, conversational output, questions, and proposals — regardless of what language the user writes in.

Spanish only for: content written to `events/` artifact files (ops reports, SQL files, CSV files) since those are audience-facing in Spanish.

**Why:** User explicitly set this rule. Mixed-language responses (Spanish questions after English analysis) are not acceptable.

**How to apply:** Every sentence Claude writes directly to the user must be in English. Only file write operations targeting `events/` use Spanish.
