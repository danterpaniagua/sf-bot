#!/usr/bin/env python3
"""PreToolUse hook, matcher "Read|Grep|Bash". DRAFT, not installed.
Event: GITIN-2307 (example for the hooks block). Denies reading the CONTENT of a dot file (a file whose name starts with ".", such as
.env, .bashrc, .netrc, .npmrc, .pgpass). Folders are not covered: listing a dot folder, or reading a normally named file inside one
(.claude/settings.json, .ssh/id_rsa), passes. Why: secrets usually live in dot files; the rule is by name, so it needs no list of secrets.
Tools: Read (file_path), Grep (path), Bash (a read command with a dot-file argument, or an input redirect from one).
Deny = exit 2 and the reason on stderr, which the assistant receives. Allowed dot files: ALLOW below.
Limits (a guardrail on text, not a security boundary, same as the other hooks of this repo):
 - a normally named file inside a dot folder passes (~/.ssh/id_rsa, ~/.aws/credentials, ~/.config/...): this is the user's choice "files, not folders";
 - a script or interpreter that opens the file itself (python3 -c "open('.env')", a program that prints it) passes;
 - variables, command substitution and other shell forms are not expanded; a failure of this hook fails open;
 - copying the file first (cp .env x) is caught because cp is a read verb; a rename (mv) is not."""
import glob, json, os, shlex, sys

ALLOW = {".gitignore", ".gitattributes", ".editorconfig", ".env.example", ".env.sample", ".dockerignore"}
# Commands whose arguments are read. The first word of each command segment is compared with this set.
READ_VERBS = {
    "cat", "tac", "head", "tail", "less", "more", "most", "nl", "bat", "batcat", "grep", "egrep", "fgrep", "rg", "ag", "sed", "awk",
    "gawk", "cut", "sort", "uniq", "wc", "strings", "xxd", "od", "hexdump", "base64", "jq", "yq", "source", ".", "cp", "scp", "rsync",
    "tar", "zip", "gzip", "zcat", "diff", "cmp", "comm", "paste", "tr", "tee", "curl", "wget", "xargs", "open", "xdg-open",
}
PREFIX_WORDS = {"sudo", "env", "nice", "time", "command", "builtin", "nohup"}
SEPARATORS = {";", "|", "||", "&&", "&", "|&", "\n", "(", ")"}


def deny(reason):
    sys.stderr.write(reason + "\n")
    sys.exit(2)


def is_dot_name(path):
    base = os.path.basename(path.rstrip("/"))
    return base.startswith(".") and base not in (".", "..") and base not in ALLOW


def dot_files(token, cwd):
    """Dot files (existing, not folders) that a path token points to; a glob token is expanded."""
    p = os.path.expanduser(token)
    if not os.path.isabs(p):
        p = os.path.join(cwd or "", p)
    hits = glob.glob(p) if any(c in p for c in "*?[") else [p]
    return [h for h in hits if is_dot_name(h) and os.path.isfile(h)]


def candidates(token):
    """A token may carry the path after '=' or '@' (curl -d @.env, --file=.env)."""
    out = {token}
    for sep in ("=", "@"):
        if sep in token:
            out.add(token.rsplit(sep, 1)[1])
    return out


def bash_hits(cmd, cwd):
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    try:
        tokens = list(lex)
    except ValueError:
        return []
    hits, segment = [], []
    segments = []
    for t in tokens:
        if t in SEPARATORS:
            segments.append(segment)
            segment = []
        else:
            segment.append(t)
    segments.append(segment)
    for seg in segments:
        i = 0
        while i < len(seg) and (seg[i] in PREFIX_WORDS or ("=" in seg[i] and not seg[i].startswith(("-", ".", "/", "~")) and seg[i].split("=")[0].isidentifier())):
            i += 1
        if i >= len(seg):
            continue
        verb = os.path.basename(seg[i])
        args = seg[i + 1:]
        # input redirect: '< file' reads it, whatever the verb is
        for j, a in enumerate(args):
            if a == "<" and j + 1 < len(args):
                for c in candidates(args[j + 1]):
                    hits += dot_files(c, cwd)
        if verb in READ_VERBS:
            for a in args:
                if a.startswith("-") and "=" not in a and "@" not in a:
                    continue
                for c in candidates(a):
                    hits += dot_files(c, cwd)
    return hits


def main():
    d = json.load(sys.stdin)
    tool, ti, cwd = d.get("tool_name", ""), d.get("tool_input") or {}, d.get("cwd", "")
    hits = []
    if tool == "Read":
        hits = dot_files(ti.get("file_path", ""), cwd) if ti.get("file_path") else []
    elif tool == "Grep":
        hits = dot_files(ti.get("path", ""), cwd) if ti.get("path") else []
    elif tool == "Bash":
        hits = bash_hits(ti.get("command", ""), cwd)
    if hits:
        deny("Reading dot files is blocked by this repo's hook (names starting with '.': .env, .bashrc, .netrc, ...). Blocked: %s. "
             "Folders are not covered. If you need a value from it, ask the user to paste only the line you need, with secrets masked." % ", ".join(sorted(set(hits))[:3]))
    sys.exit(0)


main()
