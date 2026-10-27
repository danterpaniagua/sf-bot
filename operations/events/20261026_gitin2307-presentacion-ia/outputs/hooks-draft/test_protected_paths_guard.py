#!/usr/bin/env python3
"""Local test of protected_paths_guard.py with canned tool calls. Changes nothing: it only feeds JSON to the hook and prints PASS or FAIL.
Run: python3 -I /home/dpaniagua/Documentos/git/bots/operations/events/20261026_gitin2307-presentacion-ia/outputs/hooks-draft/test_protected_paths_guard.py"""
import json, os, subprocess, sys

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "protected_paths_guard.py")
BOTS = "/home/dpaniagua/Documentos/git/bots"
HOME = os.path.expanduser("~")
MEM = HOME + "/.claude/projects/-home-dpaniagua-Documentos-git-bots/memory/note.md"

CASES = [
    # (name, tool, tool_input, env, expected)  expected: "ask" or "pass"
    ("write skill", "Write", {"file_path": BOTS + "/.claude/commands/x.md", "content": "x"}, {}, "ask"),
    ("edit root CLAUDE.md", "Edit", {"file_path": BOTS + "/CLAUDE.md", "old_string": "a", "new_string": "b"}, {}, "ask"),
    ("edit sub-project CLAUDE.md", "Edit", {"file_path": BOTS + "/operations/CLAUDE.md"}, {}, "ask"),
    ("edit hook", "Edit", {"file_path": BOTS + "/.claude/hooks/banner_guard.py"}, {}, "ask"),
    ("write settings", "Write", {"file_path": BOTS + "/.claude/settings.json"}, {}, "ask"),
    ("write settings.local", "Write", {"file_path": BOTS + "/.claude/settings.local.json"}, {}, "ask"),
    ("write agent", "Write", {"file_path": BOTS + "/.claude/agents/a.md"}, {}, "ask"),
    ("write user-level CLAUDE.md", "Write", {"file_path": HOME + "/.claude/CLAUDE.md"}, {}, "ask"),
    ("relative path with cwd", "Edit", {"file_path": "CLAUDE.md"}, {"cwd": BOTS}, "ask"),
    ("write event file", "Write", {"file_path": BOTS + "/operations/events/20261026_x/investigation.md"}, {}, "pass"),
    ("file named myCLAUDE.md", "Write", {"file_path": BOTS + "/operations/events/x/myCLAUDE.md"}, {}, "pass"),
    ("write memory (default)", "Write", {"file_path": MEM}, {}, "pass"),
    ("write memory (GUARD_MEMORY=1)", "Write", {"file_path": MEM}, {"env": {"GUARD_MEMORY": "1"}}, "ask"),
    ("bash sed -i on skill", "Bash", {"command": "sed -i 's/a/b/' " + BOTS + "/.claude/commands/ope-sre-output.md"}, {}, "ask"),
    ("bash redirect into CLAUDE.md", "Bash", {"command": "echo x >> " + BOTS + "/CLAUDE.md"}, {}, "ask"),
    ("bash cp into hooks", "Bash", {"command": "cp /tmp/h.py .claude/hooks/new.py"}, {}, "ask"),
    ("bash rm skill", "Bash", {"command": "rm .claude/commands/old.md"}, {}, "ask"),
    ("bash cat CLAUDE.md", "Bash", {"command": "cat " + BOTS + "/CLAUDE.md"}, {}, "pass"),
    ("bash grep CLAUDE.md to /tmp", "Bash", {"command": "grep -n untrusted CLAUDE.md > /tmp/o.txt"}, {}, "pass"),
    ("bash ls hooks", "Bash", {"command": "ls .claude/hooks"}, {}, "pass"),
    ("bash sed -i on event file", "Bash", {"command": "sed -i 's/a/b/' operations/events/x/investigation.md"}, {}, "pass"),
]


def run(tool, ti, extra):
    payload = {"tool_name": tool, "tool_input": ti, "cwd": extra.get("cwd", BOTS)}
    env = dict(os.environ)
    env.pop("GUARD_MEMORY", None)
    env.update(extra.get("env", {}))
    r = subprocess.run([sys.executable, "-I", HOOK], input=json.dumps(payload), capture_output=True, text=True, env=env)
    out = r.stdout.strip()
    if r.returncode == 0 and out:
        try:
            if json.loads(out)["hookSpecificOutput"]["permissionDecision"] == "ask":
                return "ask"
        except Exception:
            return "error: " + out[:80]
    return "pass" if r.returncode == 0 and not out else "error: rc=%s %s" % (r.returncode, r.stderr[:80])


bad = 0
for name, tool, ti, extra, exp in CASES:
    got = run(tool, ti, extra)
    ok = got == exp
    bad += not ok
    print("%-4s %-34s expected=%-4s got=%s" % ("PASS" if ok else "FAIL", name, exp, got))
print("\n%d cases, %d failed" % (len(CASES), bad))
sys.exit(1 if bad else 0)
