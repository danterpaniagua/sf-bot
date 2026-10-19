#!/usr/bin/env python3
"""Stop hook. DRAFT, not installed. Event: 20261014_monitoring-ai-alternatives.
Reads the assistant's last turn from the transcript. If a fenced code block holds a command that writes (SQL DML/DDL, mutating az/aws/auth0,
mutating cmdlets, APPLY=1 / -Mode apply, service control, HTTP writes, git state changes) and the code block immediately before it is not the
state-changing banner, it blocks the stop so the assistant must follow up with the banner. Limit: the turn was already shown to the user;
this hook cannot hold back the original message, it forces an immediate correction. Pattern based: prose-only code blocks that merely show
a write statement also trigger it, and a script run by name (`bash x.sh`) is judged only by its visible command line."""
import json, re, sys

MARK = "STATE-CHANGING COMMAND -- VERIFY TARGET BEFORE RUNNING"
AZ = r"create|delete|update|set|add|remove|start|stop|restart|deallocate|regenerate|purge|assign|move|swap|deploy|upgrade|rotate|reset|cancel|enable|disable"
AWSV = r"create|delete|update|put|terminate|stop|start|reboot|modify|register|deregister|attach|detach|invoke|publish|send|purge|remove|revoke|authorize|run|set|enable|disable|tag|untag|reset|restore|cancel"
WRITE = [
    re.compile(r"(?i)\b(update\s+[\w\[\]\.\"]+\s+set|delete\s+from|insert\s+into|merge\s+into|truncate\s+table|drop\s+(table|database|index|login|user)|alter\s+(table|database|index|login)|create\s+(table|index|login|user|database))\b"),
    re.compile(r"\baz\s+(?:[\w-]+\s+){1,3}(" + AZ + r")\b(?!-)"),
    re.compile(r"\baws\s+[\w-]+\s+(" + AWSV + r")-[\w-]+"),
    re.compile(r"\bauth0\b[^\n]*\b(create|delete|update|post|put|patch)\b", re.I),
    re.compile(r"\b(Start|Stop|Restart|Set|Remove|New|Enable|Disable|Move|Rename|Clear|Install|Uninstall|Copy)-[A-Za-z]+\b"),
    re.compile(r"\bAPPLY=1\b|-Mode\s+(apply|rollback)\b|--apply\b"),
    re.compile(r"\b(systemctl|service)\s+(start|stop|restart|enable|disable)\b|\bsed\s+-i\b|\brm\s+-"),
    re.compile(r"\bcurl\b[^\n]*(-X\s*(POST|PUT|PATCH|DELETE)|\s-d\s|--data)", re.I),
    re.compile(r"\bgit\s+(?:-C\s+\S+\s+)?(push|commit|reset|rebase|merge|clean|checkout|restore)\b"),
]
FENCE = re.compile(r"```[^\n]*\n(.*?)```", re.S)

def is_write(block):
    lines = [l for l in block.splitlines() if not re.match(r"^\s*(--|#|//|REM\b)", l)]
    text = "\n".join(lines)
    return any(rx.search(text) for rx in WRITE)

def last_turn_text(path):
    rows = []
    with open(path, errors="ignore") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    pass
    start = 0
    for i, r in enumerate(rows):
        if r.get("type") != "user" or r.get("isMeta"):
            continue
        c = (r.get("message") or {}).get("content")
        if isinstance(c, str) or (isinstance(c, list) and c and not any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c)):
            start = i + 1
    parts = []
    for r in rows[start:]:
        if r.get("type") == "assistant":
            for b in (r.get("message") or {}).get("content") or []:
                if isinstance(b, dict) and b.get("type") == "text":
                    parts.append(b.get("text", ""))
    return "\n\n".join(parts)

def main():
    d = json.load(sys.stdin)
    if d.get("stop_hook_active"):
        sys.exit(0)
    try:
        text = last_turn_text(d.get("transcript_path", ""))
    except OSError:
        sys.exit(0)
    blocks = FENCE.findall(text)
    bad = []
    for i, b in enumerate(blocks):
        if MARK in b or not is_write(b):
            continue
        if i == 0 or MARK not in blocks[i - 1]:
            bad.append(i + 1)
    if bad:
        print(json.dumps({"decision": "block", "reason": "A code block that changes state (block %s of this reply) is not immediately preceded by the state-changing banner. Show the banner from the root CLAUDE.md right before that command block, and say that it was missing." % ", ".join(map(str, bad))}))
    sys.exit(0)

main()
