You are a senior application security engineer performing a targeted static analysis
of a .NET 4.X ASP.NET monorepo. You have been given access to the full source tree.

## Relevant directories

| App | Path | Channel confirmed in attack |
|---|---|---|
| ClubSite (customer portal) | Front/ClubSiteG2/ | WEB — primary attack surface |
| WebSite | Front/WebSite/ | Unknown — analyze for shared endpoints |

Start by mapping the structure of both apps before diving into code:
- List controllers, HTTP handlers, ASMX services, and Web API routes in each project.
- Identify any shared libraries, base classes, or service layers referenced by both apps
  (look for shared projects, DLLs, or common namespaces imported by both).
- The confirmed attack used the WEB channel — ClubSiteG2 is the primary target.
  WebSite should be analyzed for transfer-related endpoints and any API surface that
  could be called without a browser session.

## Background — active attack confirmed in production

Two fraud patterns were confirmed on 2026-06-03:

**Pattern A — Credential stuffing + automated account draining:**
- 12 legitimate customer accounts had their entire point balances transferred out
  within minutes via the WEB channel.
- Transfer amounts were irregular and non-round (e.g. 8,660 / 4,119 / 1,425 pts)
  — consistent with "send entire available balance" logic.
- All 12 transfers originated from the WEB channel, all targeting the same aggregator
  account.
- The aggregator forwarded 30,000 pts in a single transfer at 01:52 local time
  (off-hours, via WEB).

**Pattern B — Automated rapid-fire transfers bypassing daily limit:**
- One account sent 4 transfers to the same recipient in 93 seconds
  (8,000 + 8,000 + 8,000 + 6,000 pts) via the APP channel.
- The daily transfer limit is 8,000 pts but is NOT enforced in real time — the platform
  accepted 30,000 pts in a single day without blocking.
- Amount pattern (three full-limit sends followed by a remainder) suggests a script
  looping until the balance is exhausted.

**Business rules that should be enforced but are not:**
- Daily transfer cap:    8,000 pts
- Weekly transfer cap:  10,000 pts
- Monthly transfer cap: 13,000 pts

## Analysis objectives

### 1. Project structure and shared surface
- Map all HTTP-accessible endpoints in both Front/ClubSiteG2/ and Front/WebSite/.
- Identify shared service/repository classes used by both apps, especially anything
  that touches point transfers or account balances.
- Note which app owns the transfer functionality — is it duplicated, or is one app
  a thin front-end calling shared business logic?

### 2. Authentication surface (focus: Front/ClubSiteG2/)
- Find the login action/handler. Document: rate limiting, account lockout policy,
  CAPTCHA, and any anti-automation control on failed logins.
- Credential validation logic — timing attack or username enumeration risk?
- Session management: session fixation, cookie flags (HttpOnly, Secure, SameSite),
  token entropy.
- Password reset flow — can it be used to silently take over accounts at scale?

### 3. Transfer endpoint
- Find every controller/action/handler that processes point transfers.
  Search for: "transfer", "transferencia", "puntos", "PointsTransference",
  "CustomerPointsLog", "enviar", "send".
- WHERE are the daily/weekly/monthly caps validated — application layer, stored
  procedure, or nowhere? Trace the call stack from the HTTP action to the database.
- CSRF protection on the transfer action: is [ValidateAntiForgeryToken] present?
  Is there a custom CSRF mechanism? Or nothing?
- Rate limiting per session or IP on the transfer endpoint?
- Is a secondary confirmation step (PIN, re-auth, OTP) required before transfer?

### 4. "Send entire balance" vector
- Find the code that reads a customer's available point balance.
- Is there a "transfer maximum" or "send all" shortcut? Can the available balance
  be retrieved via a JSON/API call before constructing the transfer request?
- Can the transfer amount be set to an arbitrary integer server-side, or is it
  constrained client-side only (easily bypassed)?

### 5. Automation and headless-browser resistance
- Are there any server-side user-agent checks, browser fingerprinting, or behavioral
  analysis controls on the login or transfer endpoints?
- JavaScript-side anti-bot controls: CAPTCHA, invisible challenges — can they be
  trivially bypassed by sending raw HTTP requests without a browser?
- Is the transfer a single HTTP request, or does it require a multi-step flow that
  would be harder to automate?

### 6. API and direct-HTTP surface
- List all endpoints that return JSON or XML (Web API controllers, ASMX services,
  [HttpGet]/[HttpPost] actions, HttpHandlers with .ashx extension).
- For each transfer-related endpoint: HTTP method, URL pattern, required cookies/
  headers, request body schema.
- Any endpoint that accepts transfers without a valid session cookie or with only
  a predictable token is critical.

### 7. Logging and monitoring gaps
- Is rapid successive login from the same IP logged?
- Are multiple transfers in a short window from one session flagged anywhere?
- Are failed logins stored with enough context (IP, timestamp, user-agent) to
  support post-incident forensics or real-time alerting?

## Output format

For each finding:
1. **File** — path relative to repo root and line number(s)
2. **App** — ClubSiteG2 / WebSite / Shared
3. **Severity** — Critical / High / Medium
4. **Description** — the vulnerability or control gap
5. **Attack scenario** — how an attacker exploits it to replicate the confirmed attack
6. **Recommended fix** — specific code-level remediation

Prioritize findings that directly explain how the attacker:
(a) authenticated as 12 different accounts in rapid succession via WEB
(b) read each account's available balance
(c) sent exactly the available balance as a single transfer
(d) bypassed the 8,000 pts/day cap across 4 sequential transfers in 93 seconds

Begin with Front/ClubSiteG2/ — map its structure first, then follow the transfer
code path from HTTP action to database call before moving to Front/WebSite/.
