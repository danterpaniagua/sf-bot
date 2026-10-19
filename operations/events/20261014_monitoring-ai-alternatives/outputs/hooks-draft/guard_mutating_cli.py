#!/usr/bin/env python3
"""PreToolUse hook, matcher "Bash". DRAFT, not installed. Event: 20261014_monitoring-ai-alternatives.

The assistant never runs anything that changes a real system: database clients, mutating cloud/API/CLI calls, remote shells and
git state changes are denied (exit 2, reason on stderr); commands that could discard local work ask first (permissionDecision "ask").
Reads and local file work pass. Scripts and `python -c`/heredoc code are scanned for the same patterns; a script that has an APPLY
dry-run gate is allowed only without `APPLY=1`. This is a guardrail on command text, not a security boundary: use read-only
credentials for the real boundary. Known limits: quoted text is masked before splitting, obfuscated commands pass.
"""
import json, os, re, shlex, sys

def deny(reason):
    sys.stderr.write("Blocked by guard_mutating_cli: " + reason + "\n"); sys.exit(2)

def ask(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": reason}})); sys.exit(0)

DB = {"sqlcmd", "mongosh", "mongo", "psql", "mysql", "mariadb", "sqlplus", "bcp", "redis-cli"}
REMOTE = {"ssh", "scp", "sftp", "rsync"}
WRAPPERS = {"sudo", "time", "command", "nohup", "exec", "xargs", "env", "nice", "timeout", "stdbuf", "watch"}
INTERP = {"bash", "sh", "zsh", "python", "python3", "pwsh", "powershell", "node", "ruby"}
AZ_VERBS = r"create|delete|update|set|add|remove|start|stop|restart|deallocate|regenerate|purge|assign|move|swap|deploy|upgrade|rotate|reset|cancel|enable|disable|import"
AWS_VERBS = r"create|delete|update|put|terminate|stop|start|reboot|modify|register|deregister|attach|detach|invoke|publish|send|purge|remove|revoke|authorize|run|set|enable|disable|tag|untag|reset|restore|cancel"
GIT_DENY = {"add", "commit", "push", "reset", "rebase", "merge", "clean", "rm", "tag", "cherry-pick", "am", "apply", "revert"}
GIT_ASK = {"checkout", "restore", "switch", "stash"}
QUOTED = re.compile(r"""'[^']*'|"(?:[^"\\]|\\.)*\"""")
SPLIT = re.compile(r"\s*(?:&&|\|\||;|\||\n|\$\(|`)\s*")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n(.*?)\n\s*\2\b", re.S)
APPLY_FLAG = re.compile(r"\bAPPLY=1\b|--apply\b|-Mode\s+(apply|rollback)\b|\bAPPLY\s*=\s*['\"]?1")

CONTENT_RULES = [
    ("database client or driver", re.compile(r"\b(sqlcmd|mongosh|psql|mysql|sqlplus|pyodbc|pymssql|pymongo|psycopg2)\b")),
    ("az mutation", re.compile(r"\baz\s+(?:[\w-]+\s+){1,3}(" + AZ_VERBS + r")\b(?!-)")),
    ("aws mutation", re.compile(r"\baws\s+[\w-]+\s+(" + AWS_VERBS + r")-[\w-]+")),
    ("HTTP write", re.compile(r"\bcurl\b[^\n]*(-X\s*(POST|PUT|PATCH|DELETE)|--request\s*(POST|PUT|PATCH|DELETE)|\s-d\s|--data)|requests\.(post|put|patch|delete)\(|method\s*=\s*[\"']?(POST|PUT|PATCH|DELETE)|api\(\s*[\"'](PUT|POST|PATCH|DELETE)[\"']", re.I)),
    ("git state change", re.compile(r"\bgit\s+(?:-C\s+\S+\s+)?(add|commit|push|reset|rebase|merge|clean|tag)\b")),
    ("service control", re.compile(r"\bsystemctl\s+(start|stop|restart|enable|disable)\b|\b(Start|Stop|Restart|Set|Remove)-(Service|Item|ItemProperty)\b")),
    ("remote shell", re.compile(r"\b(ssh|scp|sftp)\s+\S")),
    ("recursive delete", re.compile(r"\brm\s+-[a-zA-Z]*[rR]")),
]

PY_RULES = [
    ("database driver", re.compile(r"(?m)^\s*(?:import|from)\s+(pyodbc|pymssql|pymongo|psycopg2|mysql\.connector|cx_Oracle)\b")),
    ("subprocess call to a mutating tool", re.compile(r"(?:subprocess\.\w+|os\.system|os\.popen)\([^\n]*\b(sqlcmd|mongosh|psql|mysql|ssh|scp|rsync|git\s+(add|commit|push|reset)|az\s+\S+\s+\S*(create|delete|update|set)|aws\s+\S+\s+(" + AWS_VERBS + r")-)")),
    ("HTTP write", re.compile(r"requests\.(post|put|patch|delete)\(|method\s*=\s*[\"']?(POST|PUT|PATCH|DELETE)|\bapi\(\s*[\"'](PUT|POST|PATCH|DELETE)[\"']", re.I)),
]

def head(tokens):
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1; continue
        if os.path.basename(t) in WRAPPERS:
            i += 1
            while i < len(tokens) and (tokens[i].startswith("-") or re.match(r"^\d+[smhd]?$", tokens[i])):
                i += 1
            continue
        return os.path.basename(t), tokens[i + 1:]
    return None, []

def toks(seg):
    try:
        return shlex.split(seg)
    except ValueError:
        return seg.split()

MUT_CMD = re.compile(r"\b(sqlcmd|mongosh|psql|mysql|ssh|scp|rsync)\b|\bgit\s+(add|commit|push|reset)\b|\baz\s+\S+\s+\S*(create|delete|update|set)\b|\baws\s+\S+\s+(" + AWS_VERBS + r")-")
DB_DRIVERS = {"pyodbc", "pymssql", "pymongo", "psycopg2", "cx_Oracle"}

def py_ast_hit(text):
    import ast
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return "fallback"
    def strings(node):
        return [n.value for n in ast.walk(node) if isinstance(n, ast.Constant) and isinstance(n.value, str)]
    for n in ast.walk(tree):
        if isinstance(n, ast.Import) and any(a.name.split(".")[0] in DB_DRIVERS for a in n.names):
            return "database driver"
        if isinstance(n, ast.ImportFrom) and (n.module or "").split(".")[0] in DB_DRIVERS:
            return "database driver"
        if isinstance(n, ast.Call):
            f = n.func
            name = (f.value.id + "." + f.attr) if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) else (f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", ""))
            if name in ("requests.post", "requests.put", "requests.patch", "requests.delete"):
                return "HTTP write"
            if name.startswith("subprocess.") or name in ("os.system", "os.popen"):
                joined = " ".join(" ".join(strings(a)) for a in n.args)
                if MUT_CMD.search(joined):
                    return "subprocess call to a mutating tool"
            for kw in n.keywords:
                if kw.arg == "method" and isinstance(kw.value, ast.Constant) and str(kw.value.value).upper() in ("POST", "PUT", "PATCH", "DELETE"):
                    return "HTTP write (method=...)"
            if name == "api" and n.args and isinstance(n.args[0], ast.Constant) and str(n.args[0].value).upper() in ("POST", "PUT", "PATCH", "DELETE"):
                return "HTTP write (api call)"
    return None

def scan_content(text, label, kind="sh"):
    if re.search(r"\bAPPLY\b", text) and not APPLY_FLAG.search(label):
        # has a dry-run gate: only the apply run mutates
        return None
    if kind == "py":
        hit = py_ast_hit(text)
        if hit != "fallback":
            return hit
    for name, rx in (PY_RULES if kind == "py" else CONTENT_RULES):
        if rx.search(text):
            return name
    return None

def kind_of(interp, path=""):
    if path.endswith(".py") or interp in ("python", "python3", "node", "ruby"):
        return "py"
    return "sh"

def main():
    data = json.load(sys.stdin)
    cmd = (data.get("tool_input") or {}).get("command") or ""
    # heredocs: bodies are code (interpreters) or file content (cat/tee)
    bodies = []
    for m in HEREDOC.finditer(cmd):
        line_start = cmd.rfind("\n", 0, m.start()) + 1
        consumer, _ = head(toks(QUOTED.sub('"_"', cmd[line_start:m.start()])))
        bodies.append((consumer, m.group(3)))
    stripped = HEREDOC.sub("", cmd)
    masked = QUOTED.sub('"_"', stripped)
    if APPLY_FLAG.search(masked):
        deny("APPLY=1 / apply mode changes real systems; the user runs it after reviewing the dry run")
    for seg in SPLIT.split(masked):
        if not seg.strip():
            continue
        cmdname, args = head(toks(seg))
        if not cmdname:
            continue
        if cmdname in DB:
            deny("%s is a database client: the assistant never runs database commands; give the SQL as a reviewed copy-paste block" % cmdname)
        if cmdname in REMOTE:
            deny("%s opens a remote shell or copies to a remote host: the user runs those" % cmdname)
        if cmdname == "az":
            if re.search(r"\brest\b", seg) and re.search(r"--method\s*(put|post|patch|delete)\b", seg, re.I):
                deny("az rest with a write method")
            if any(re.fullmatch(AZ_VERBS, a) for a in args if not a.startswith("-")):
                deny("az command with a mutating verb")
        if cmdname == "aws":
            pos = [a for a in args if not a.startswith("-")]
            if len(pos) >= 2 and re.match(r"(" + AWS_VERBS + r")-", pos[1]):
                deny("aws command with a mutating operation (%s)" % pos[1])
            if len(pos) >= 3 and pos[0] == "s3" and pos[1] in ("rm", "mv", "rb", "mb"):
                deny("aws s3 %s changes buckets or objects" % pos[1])
            if len(pos) >= 3 and pos[0] == "s3" and pos[1] in ("cp", "sync") and pos[-1].startswith("s3://"):
                deny("aws s3 %s uploads to a bucket" % pos[1])
        if cmdname == "auth0":
            if re.search(r"\b(post|put|patch|delete)\b", seg, re.I) or any(re.fullmatch(r"create|delete|update", a) for a in args):
                deny("auth0 command that writes to the tenant")
        if cmdname in ("curl", "wget", "http", "https", "xh"):
            if re.search(r"(-X|--request|--method)[ =]*(POST|PUT|PATCH|DELETE)\b|(^|\s)(-d|-F|-T|--data\S*|--form|--upload-file|--post-data|--post-file|--json)(\s|=|$)", seg, re.I):
                deny("HTTP request that writes (POST/PUT/PATCH/DELETE or a body); reads (GET) are allowed")
        if cmdname == "git":
            rest = [a for a in args]
            i = 0
            while i < len(rest) and rest[i].startswith("-"):
                i += 2 if rest[i] in ("-C", "-c") else 1
            sub = rest[i] if i < len(rest) else ""
            if sub in GIT_DENY:
                deny("git %s changes repository state; the user runs it (clones are never committed or pushed)" % sub)
            if sub == "branch" and any(a in ("-d", "-D", "-m", "-M") for a in rest):
                deny("git branch delete/rename")
            if sub in GIT_ASK:
                ask("git %s can discard local work" % sub)
        if cmdname in ("systemctl", "service") and re.search(r"\b(start|stop|restart|reload|enable|disable|mask|daemon-reload)\b", seg):
            deny("service control")
        if cmdname == "docker" and re.search(r"\b(rm|rmi|stop|kill|prune|run|exec|compose)\b", seg):
            deny("docker command that changes containers")
        if cmdname == "kubectl" and re.search(r"\b(apply|delete|patch|replace|scale|rollout|exec|edit|drain|cordon)\b", seg):
            deny("kubectl write")
        if cmdname == "terraform" and re.search(r"\b(apply|destroy|import|taint|untaint|state)\b", seg):
            deny("terraform state change (plan is fine)")
        if cmdname in ("pwsh", "powershell") and re.search(r"\b(Start|Stop|Restart|Set|Remove|New|Enable|Disable|Move|Rename|Clear|Invoke)-[A-Za-z]+", cmd):
            deny("PowerShell with a mutating cmdlet")
        if cmdname == "rm":
            targets = [a for a in args if not a.startswith("-")]
            if not targets or not all(t.startswith("/tmp/") for t in targets):
                ask("rm outside /tmp")
        if cmdname in INTERP and cmdname in ("bash", "sh", "zsh") and "-n" in args:
            continue  # syntax check only, nothing runs
        if cmdname in INTERP:
            pos = [a for a in args if not a.startswith("-")]
            if "-c" in args:
                # the masked copy hides quoted text, so take the -c code from the unmasked command
                m = re.search(r"""\s-c\s+(?:'([^']*)'|"((?:[^"\\]|\\.)*)")""", stripped)
                code = (m.group(1) or m.group(2) or "") if m else ""
                hit = scan_content(code, cmd, kind_of(cmdname))
                if hit:
                    deny("inline code matches: " + hit)
            elif pos and os.path.isfile(pos[0]):
                try:
                    text = open(pos[0], errors="ignore").read(262144)
                except OSError:
                    text = ""
                hit = scan_content(text, cmd, kind_of(cmdname, pos[0]))
                if hit:
                    deny("script %s matches: %s, and it has no APPLY dry-run gate; the user runs it" % (os.path.basename(pos[0]), hit))
    for consumer, body in bodies:
        if consumer in INTERP:
            hit = scan_content(body, cmd, kind_of(consumer))
            if hit:
                deny("heredoc code for %s matches: %s" % (consumer, hit))
    sys.exit(0)

main()
