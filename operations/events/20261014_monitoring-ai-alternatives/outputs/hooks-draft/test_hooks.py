#!/usr/bin/env python3
"""Runs the three draft hooks against sample inputs. Local only: no network, no writes outside a temp dir."""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
fails = 0

def run(script, payload):
    p = subprocess.run([sys.executable, os.path.join(HERE, script)], input=json.dumps(payload), capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr

def check(name, got, want):
    global fails
    ok = got == want
    fails += 0 if ok else 1
    print("%-4s %-52s got=%s want=%s" % ("ok" if ok else "FAIL", name, got, want))

def bash(cmd): return {"tool_name": "Bash", "tool_input": {"command": cmd}}
def verdict(script, payload):
    rc, out, _ = run(script, payload)
    if rc == 2: return "deny"
    if rc == 0 and '"ask"' in out: return "ask"
    return "allow" if rc == 0 else "rc%d" % rc

print("== guard_mutating_cli.py")
tmp = tempfile.mkdtemp()
gated = os.path.join(tmp, "gated.py"); open(gated, "w").write('import os\nAPPLY = os.environ.get("APPLY")\napi("PUT", "/x")\n')
ungated = os.path.join(tmp, "ungated.sh"); open(ungated, "w").write('#!/bin/bash\ncurl -X POST https://x/y -d @f\n')
safe = os.path.join(tmp, "safe.sh"); open(safe, "w").write('#!/bin/bash\ncurl -s https://x/y\naz monitor metrics list --resource r\n')
cases = [
    ("ls -la", "allow"), ("grep -n sqlcmd notes.md", "allow"), ("git status", "allow"), ("git -C loyalty log --oneline -5", "allow"),
    ("git pull --ff-only origin develop", "allow"), ("git add -A", "deny"), ("git -C x commit -m 'm'", "deny"), ("git push origin main", "deny"),
    ("git checkout -- file", "ask"), ("sqlcmd -S h -Q 'select 1'", "deny"), ("/opt/mssql-tools/bin/sqlcmd -S h", "deny"), ("mongosh $URI", "deny"),
    ("ssh gadmin@host 'ls'", "deny"), ("az vm list -o table", "allow"), ("az monitor diagnostic-settings list --resource r", "allow"),
    ("az webapp config set -g g -n n", "deny"), ("az group delete -n g", "deny"), ("az rest --method post --url u", "deny"), ("az rest --url u", "allow"),
    ("aws sqs list-queues", "allow"), ("aws cloudwatch get-metric-statistics --start-time x", "allow"), ("aws sqs delete-queue --queue-url u", "deny"),
    ("aws s3 cp s3://b/k ./k", "allow"), ("aws s3 cp ./k s3://b/k", "deny"), ("aws s3 rm s3://b/k", "deny"), ("auth0 api get clients", "allow"),
    ("auth0 api post clients", "deny"), ("curl -s https://api.github.com/x", "allow"), ("curl -X POST https://x -d '{}'", "deny"), ("curl -d a=b https://x", "deny"),
    ("systemctl restart logstash", "deny"), ("terraform plan", "allow"), ("terraform apply", "deny"), ("rm -f /tmp/a.txt", "allow"), ("rm -rf data", "ask"),
    ("APPLY=1 python3 widgets_path.py", "deny"), ("python3 %s" % gated, "allow"), ("APPLY=1 python3 %s" % gated, "deny"), ("bash %s" % ungated, "deny"), ("bash %s" % safe, "allow"),
    ("python3 -c 'import pymssql'", "deny"), ("python3 -c 'print(1)'", "allow"),
    ("python3 - <<'EOF'\nimport json\nprint(1)\nEOF", "allow"), ("python3 - <<'EOF'\nimport pyodbc\nEOF", "deny"),
    ("python3 - <<'EOF'\ntext = 'run sqlcmd -S h; az group delete -n g'\nopen('/tmp/n.md','w').write(text)\nEOF", "allow"),
    ("python3 - <<'EOF'\nimport subprocess\nsubprocess.run(['sqlcmd', '-S', 'h'])\nEOF", "deny"),
    ("python3 - <<'EOF'\nimport requests\nrequests.post('https://x')\nEOF", "deny"),
    ("python3 -c 'print(\"use sqlcmd later\")'", "allow"),
    ("bash -n /nonexistent/ungated.sh", "allow"),
    ("bash -n %s" % ungated, "allow"),
    ("cat > /tmp/doc.md <<'EOF'\nrun with APPLY=1 to change things\nEOF", "allow"),
    ("sed -i 's/old/APPLY=1 text/' /tmp/doc.md", "allow"),
    ("python3 - <<'EOF'\nsrc = \"subprocess.run(['sqlcmd'])\"\nopen('/tmp/n.py','w').write(src)\nEOF", "allow"),
    ("cat > /tmp/x.sh <<'EOF'\naz group delete -n g\nEOF", "allow"), ("echo done && ls", "allow"),
]
for cmd, want in cases:
    check(cmd.replace("\n", "\\n")[:52], verdict("guard_mutating_cli.py", bash(cmd)), want)

print("== guard_secrets_in_writes.py")
S = "/home/u/bots/loyalty/events/e1/data/out.txt"
secret_pw = "Password=" + "Xk9" + "pQ2vL7"          # built at run time so this file holds no secret-looking literal
cases = [
    ("Write plain text", {"tool_name": "Write", "tool_input": {"file_path": S, "content": "host SFDEV02 ok"}}, "allow"),
    ("Write masked password", {"tool_name": "Write", "tool_input": {"file_path": S, "content": "Password=***;Server=x"}}, "allow"),
    ("Write placeholder password", {"tool_name": "Write", "tool_input": {"file_path": S, "content": "Password=<redacted>"}}, "allow"),
    ("Write env var", {"tool_name": "Write", "tool_input": {"file_path": S, "content": "Password=$DB_PASS"}}, "allow"),
    ("Write real-looking password", {"tool_name": "Write", "tool_input": {"file_path": S, "content": "x;" + secret_pw + ";y"}}, "deny"),
    ("Write quoted password", {"tool_name": "Write", "tool_input": {"file_path": S, "content": "Password='" + "Xk9pQ2vL7" + "'"}}, "deny"),
    ("Write outside scope", {"tool_name": "Write", "tool_input": {"file_path": "/tmp/scratch.txt", "content": secret_pw}}, "allow"),
    ("Edit event key", {"tool_name": "Edit", "tool_input": {"file_path": S, "new_string": "SharedAccess" + "Key=" + "A" * 30}}, "deny"),
    ("Write private key header", {"tool_name": "Write", "tool_input": {"file_path": S, "content": "-----BEGIN RSA " + "PRIVATE KEY-----"}}, "deny"),
    ("Write AWS key id", {"tool_name": "Write", "tool_input": {"file_path": S, "content": "AKIA" + "ABCDEFGHIJKLMNOP"}}, "deny"),
    ("Write JWT", {"tool_name": "Write", "tool_input": {"file_path": S, "content": "eyJhbGciOiJIUzI1NiJ9" + ".eyJzdWIiOiIxMjM0NTY3ODkwIn0" + ".SflKxwRJSMeKKF2QT4fwpM"}}, "deny"),
    ("Write mask regex source (no value)", {"tool_name": "Write", "tool_input": {"file_path": S, "content": "-replace '(?i)(password|pwd)\\s*=\\s*(''[^'']*''|[^;]+)', '$1=***'"}}, "allow"),
    ("Bash heredoc into events with secret", bash("cat > /x/events/e/data/f.txt <<'EOF'\n" + secret_pw + "\nEOF"), "deny"),
    ("Bash unrelated", bash("ls /x/events"), "allow"),
    ("Write Spanish note on the masking", {"tool_name": "Write", "tool_input": {"file_path": S, "content": "pasa por el enmascarado de Password=/Pwd= (con comillas simples, dobles o sin comillas)"}}, "allow"),
    ("Write docs about the masking (Password=/Pwd=)", {"tool_name": "Write", "tool_input": {"file_path": S, "content": "# se enmascara Password=/Pwd= por si acaso"}}, "allow"),
]
for name, payload, want in cases:
    check(name, verdict("guard_secrets_in_writes.py", payload), want)

print("== banner_guard.py")
def transcript(assistant_text):
    rows = [{"type": "user", "message": {"role": "user", "content": "do it"}},
            {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": assistant_text}]}}]
    p = os.path.join(tmp, "t.jsonl"); open(p, "w").write("\n".join(json.dumps(r) for r in rows)); return p
BANNER = "```\n+----+\n|  STATE-CHANGING COMMAND -- VERIFY TARGET BEFORE RUNNING    |\n+----+\n```\n"
def stop(text, active=False):
    rc, out, _ = run("banner_guard.py", {"transcript_path": transcript(text), "stop_hook_active": active})
    return "block" if '"block"' in out else "allow"
upd = "```sql\nUPDATE Sch.Task SET ExecuteOn = GETDATE() WHERE Id = 1;\n```\n"
cases = [
    ("read-only SQL, no banner", "Run:\n```sql\nSELECT TOP 5 * FROM Sch.Task;\n```\n", "allow"),
    ("UPDATE without banner", "Run:\n" + upd, "block"),
    ("UPDATE with banner right before", "Run:\n" + BANNER + upd, "allow"),
    ("banner far before, text between", "Banner:\n" + BANNER + "Then another block:\n```bash\nls\n```\n" + upd, "block"),
    ("APPLY=1 without banner", "```bash\nAPPLY=1 python3 widgets_path.py\n```\n", "block"),
    ("APPLY=1 with banner", BANNER + "```bash\nAPPLY=1 python3 widgets_path.py\n```\n", "allow"),
    ("aws delete without banner", "```bash\naws sqs delete-queue --queue-url u\n```\n", "block"),
    ("commented write only", "```sql\n-- UPDATE x SET a=1\nSELECT 1;\n```\n", "allow"),
    ("service restart in PowerShell", "```powershell\nRestart-Service Foo\n```\n", "block"),
    ("no code blocks", "plain prose with UPDATE x SET", "allow"),
]
for name, text, want in cases:
    check(name, stop(text), want)
check("stop_hook_active skips the check", stop("Run:\n" + upd, active=True), "allow")
print("\nFAILED: %d" % fails); sys.exit(1 if fails else 0)
