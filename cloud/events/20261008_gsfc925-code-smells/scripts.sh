#!/usr/bin/env bash
# Event: 20261008_gsfc925-code-smells

# === GIT (clon local en cloud/repo/SmartFran.Cloud; salidas en data/) ===
# C1 — git fetch --all --prune → data/git-fetch.txt (modifica solo refs remotas; el arbol de trabajo queda en main)
# C2 — git branch -a --list '*925*' → data/git-branches-925.txt
# Lecturas posteriores (git log / git show / git diff sobre origin/feature/gsfc-925) fueron de solo lectura.
