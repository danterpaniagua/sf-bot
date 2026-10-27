#!/bin/sh
# Event: 20261026_gitin2315-node-20-to-22-upgrade
# Read-only inspection of the packages installed inside the image; it is fed to `sh -s` in the container
# (see C9 in scripts.sh), so it must stay POSIX sh and print only versions, never file contents.
cd /usr/src/app || exit 1

echo "## node / npm"
node --version
npm --version

echo "## lockfile and package.json in the image"
ls -la package.json package-lock.json 2>&1
node -p "const p=require('./package.json'); ['body-parser','express','express-jwt','jsonwebtoken','lodash.set','axios'].map(k=>k+' '+(p.dependencies[k]||'-')).join('\n')"

echo "## npm ls (production tree)"
npm ls body-parser express express-jwt jsonwebtoken lodash.set axios --all 2>&1 | head -60

echo "## every installed copy of the packages in the Trivy findings"
find / -type d \( -name body-parser -o -name undici -o -name brace-expansion -o -name http-cache-semantics -o -name lodash.set -o -name express-jwt -o -name jsonwebtoken \) -path '*node_modules*' -not -path '/proc/*' 2>/dev/null | sort | while read -r d; do
  if [ -f "$d/package.json" ]; then
    echo "$d $(node -p "require('$d/package.json').version")"
  fi
done
