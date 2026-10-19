#!/usr/bin/env python3
"""PreToolUse hook, matcher "Write|Edit|MultiEdit" (and "Bash" when the command targets repo context files). DRAFT, not installed.
Event: 20261014_monitoring-ai-alternatives. Denies content that looks like a real secret before it reaches events/, docs/, CLAUDE.md or
skills (exit 2). The reason names the pattern class, never the value. Placeholders (***, <...>, $VAR, ${VAR}) pass.
Limit: it checks what the assistant writes; it does not see what the user pastes, nor a script handed to the user (a masking regex that
misses a quoted password is only caught by testing the regex: see test_hooks.py case `mask_regex`)."""
import json, re, sys

PATTERNS = [
    ("password value", re.compile(r"""(?i)\b(password|pwd|passwd)\b\s*=\s*(?!\*{3}|<|\$|\{|%|[/,|()\]]|['"]?\*{3}|['"]?<)['"]?[^\s;'"*<>$}{]{4,}""")),
    ("password in JSON", re.compile(r"""(?i)"(password|pwd|passwd|secret)"\s*:\s*"(?!\*{3}|<)[^"]{4,}"
""".strip())),
    ("Azure/Event Hub key", re.compile(r"(?i)(SharedAccessKey|AccountKey)\s*=\s*(?!\*{3}|<)[A-Za-z0-9+/=]{12,}")),
    ("private key block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("AWS access key id", re.compile(r"\b(AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("JWT", re.compile(r"\beyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{10,}")),
    ("GitHub/Slack token", re.compile(r"\b(ghp_[A-Za-z0-9]{30,}|xox[baprs]-[A-Za-z0-9-]{10,})")),
    ("Authorization header", re.compile(r"(?i)authorization:\s*(bearer|basic)\s+(?!\*|<|\$)[A-Za-z0-9._~+/=-]{12,}")),
    ("API key or secret assignment", re.compile(r"""(?i)\b(api[_-]?key|client[_-]?secret|secret[_-]?key)\b\s*=\s*['"]?(?!\*{3}|<|\$)[A-Za-z0-9/+_-]{20,}""")),
]
SCOPE = re.compile(r"/events/|/docs/|CLAUDE\.md$|/\.claude/commands/|/\.claude/hooks/")

def main():
    d = json.load(sys.stdin)
    ti = d.get("tool_input") or {}
    tool = d.get("tool_name", "")
    texts = []
    path = ti.get("file_path", "")
    if tool in ("Write", "Edit", "MultiEdit"):
        if not SCOPE.search(path):
            sys.exit(0)
        texts += [ti.get("content", ""), ti.get("new_string", "")] + [e.get("new_string", "") for e in ti.get("edits", []) if isinstance(e, dict)]
    elif tool == "Bash":
        cmd = ti.get("command", "")
        if not re.search(r"/events/|/docs/|CLAUDE\.md|\.claude/(commands|hooks)/", cmd) or not re.search(r">|tee\s|sed\s+-i|python3?\s+-", cmd):
            sys.exit(0)
        texts.append(cmd)
    hits = sorted({name for t in texts for name, rx in PATTERNS if rx.search(t or "")})
    if hits:
        sys.stderr.write("Blocked by guard_secrets_in_writes: the content matches secret pattern(s): %s. Do not write the value; redact it (***) or refer to it by name and purpose (root CLAUDE.md, secrets rule).\n" % ", ".join(hits))
        sys.exit(2)
    sys.exit(0)

main()
