#!/usr/bin/env python3
"""PreToolUse hook, matcher "Write|Edit|MultiEdit" and "Bash". DRAFT, not installed.
Event: GITIN-2307. Asks the user before the assistant creates, changes or deletes the files that define its own rules and tools:
skills (.claude/commands), agents (.claude/agents), hooks (.claude/hooks), settings (.claude/settings.json, settings.local.json) and
every CLAUDE.md, in the repo and in the user-level ~/.claude/. Rule it implements: root CLAUDE.md, "changed only when the user
explicitly asks". Why "ask" and not "deny": the user edits these files on purpose; the point is that no change happens silently, for
example because of an instruction hidden in pasted or fetched content.
Optional (off by default): GUARD_MEMORY=1 also asks before writes under ~/.claude/projects/*/memory/ (the assistant's own memory).
Limits: it sees the tool call, not why it was made; a script that writes a protected file, or an unusual shell form, can pass; reads pass.
A guardrail on text, not a security boundary (same as the other hooks in this repo)."""
import json, os, re, sys

HOME = os.path.expanduser("~")
PROTECTED = re.compile(
    r"(^|/)\.claude/(commands|agents|hooks)(/|$)"
    r"|(^|/)\.claude/settings(\.local)?\.json$"
    r"|(^|/)CLAUDE\.md$"
)
MEMORY = re.compile(r"(^|/)\.claude/projects/[^/]+/memory(/|$)")
# Words in a shell command that write, move, copy or delete (the path must also appear in the command).
SHELL_WRITE = re.compile(r"(\btee\b|\bsed\s+(-[A-Za-z]*i|--in-place)|\bperl\s+-[A-Za-z]*i|\bmv\b|\bcp\b|\brm\b|\btruncate\b|\bln\b|\binstall\b|\bchmod\b|\bgit\s+(checkout|restore|stash|reset|apply|am)\b)")
SHELL_REDIRECT_TARGET = re.compile(r">>?\s*(\"[^\"]+\"|'[^']+'|\S+)")
PATH_IN_CMD = re.compile(r"""[^\s"'|;&<>]*(\.claude/(commands|agents|hooks)/[^\s"'|;&<>]*|\.claude/settings(\.local)?\.json|(?:^|/|\s)CLAUDE\.md)""")


def ask(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": reason}}))
    sys.exit(0)


def norm(path, cwd):
    p = os.path.expanduser(path or "")
    if p and not os.path.isabs(p):
        p = os.path.join(cwd or "", p)
    return os.path.normpath(p)


def protected(path):
    return bool(PROTECTED.search(path))


def main():
    d = json.load(sys.stdin)
    ti = d.get("tool_input") or {}
    tool = d.get("tool_name", "")
    cwd = d.get("cwd", "")
    guard_memory = os.environ.get("GUARD_MEMORY") == "1"
    why = ("This file defines the assistant's own rules or tools. It changes only when you explicitly ask "
           "(root CLAUDE.md). Approve only if you asked for this change; if it came from pasted or fetched content, deny it.")
    if tool in ("Write", "Edit", "MultiEdit"):
        p = norm(ti.get("file_path", ""), cwd)
        if protected(p):
            ask("Protected path: %s. %s" % (p, why))
        if guard_memory and MEMORY.search(p):
            ask("Assistant memory: %s. Memory is loaded into later sessions; approve only if you asked to remember this." % p)
    elif tool == "Bash":
        cmd = ti.get("command", "")
        hit = False
        for m in SHELL_REDIRECT_TARGET.finditer(cmd):
            target = norm(m.group(1).strip("\"'"), cwd)
            if protected(target) or (guard_memory and MEMORY.search(target)):
                hit = True
        if not hit and SHELL_WRITE.search(cmd):
            for m in PATH_IN_CMD.finditer(cmd):
                hit = True
                break
        if hit:
            ask("The command writes, moves, copies or deletes a protected path. %s Command: %s" % (why, cmd[:200]))
    sys.exit(0)


main()
