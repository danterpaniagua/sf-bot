#!/usr/bin/env node
// npm dependency compliance check — see .claude/commands/sp-npm-compliance.md
// Usage: node npm_compliance_check.mjs <package.json path> <dockerfile-node-major-or-NA> <label>

import { readFileSync, writeFileSync } from 'fs';

const [, , pkgJsonPath, dockerNodeMajor, label] = process.argv;

function parseVersion(v) {
  const m = /^(\d+)\.(\d+)\.(\d+)/.exec(v);
  if (!m) return null;
  return [Number(m[1]), Number(m[2]), Number(m[3])];
}
function cmp(a, b) {
  for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] - b[i];
  return 0;
}
function satisfiesRange(version, range) {
  const v = parseVersion(version);
  if (!v) return false;
  range = range.trim();
  if (range.startsWith('^')) {
    const r = parseVersion(range.slice(1));
    if (!r) return false;
    if (r[0] > 0) return v[0] === r[0] && cmp(v, r) >= 0;
    if (r[1] > 0) return v[0] === 0 && v[1] === r[1] && cmp(v, r) >= 0;
    return v[0] === 0 && v[1] === 0 && v[2] === r[2];
  }
  if (range.startsWith('~')) {
    const r = parseVersion(range.slice(1));
    if (!r) return false;
    return v[0] === r[0] && v[1] === r[1] && cmp(v, r) >= 0;
  }
  if (range === '*' || range === '') return true;
  // bare version = exact match per npm semver rules
  const r = parseVersion(range);
  if (!r) return false;
  return cmp(v, r) === 0;
}
function maxSatisfying(versions, range) {
  const candidates = versions.filter((v) => satisfiesRange(v, range));
  if (candidates.length === 0) return null;
  return candidates.sort((a, b) => cmp(parseVersion(a), parseVersion(b))).pop();
}
function engineFloor(engines) {
  if (!engines || !engines.node) return null;
  const nums = [...engines.node.matchAll(/(\d+)(?:\.\d+)*/g)].map((m) => Number(m[1]));
  return nums.length ? Math.min(...nums) : null;
}

async function fetchPkg(name) {
  const res = await fetch(`https://registry.npmjs.org/${encodeURIComponent(name).replace('%40', '@')}`);
  if (!res.ok) throw new Error(`${name}: HTTP ${res.status}`);
  return res.json();
}

const SEV_RANK = { UNKNOWN: 0, LOW: 1, MODERATE: 2, HIGH: 3, CRITICAL: 4 };
function cvssToLabel(vector) {
  // Rough CVSS v3/v4 base-score-free fallback: only used when database_specific.severity is absent.
  // Not a real score calculation — just enough to not silently drop a vuln with no label at all.
  return 'UNKNOWN';
}
async function osvQuery(name, version) {
  const res = await fetch('https://api.osv.dev/v1/query', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ package: { name, ecosystem: 'npm' }, version }),
  });
  if (!res.ok) return { count: 0, maxSeverity: 'UNKNOWN', worst: null, error: `HTTP ${res.status}` };
  const data = await res.json();
  const vulns = data.vulns || [];
  let maxSeverity = 'UNKNOWN';
  let worst = null;
  const bySeverity = { CRITICAL: 0, HIGH: 0, MODERATE: 0, LOW: 0, UNKNOWN: 0 };
  for (const v of vulns) {
    const label = (v.database_specific?.severity || cvssToLabel(v.severity?.[0]?.score)).toUpperCase();
    bySeverity[label] = (bySeverity[label] ?? 0) + 1;
    if ((SEV_RANK[label] ?? 0) > (SEV_RANK[maxSeverity] ?? 0)) {
      maxSeverity = label;
      worst = { id: v.id, summary: v.summary };
    }
  }
  return { count: vulns.length, maxSeverity, worst, bySeverity };
}

async function main() {
  const pkgJson = JSON.parse(readFileSync(pkgJsonPath, 'utf8'));
  const deps = pkgJson.dependencies || {};
  const rows = [];
  const names = Object.keys(deps).sort();

  for (const name of names) {
    const range = deps[name];
    try {
      const doc = await fetchPkg(name);
      const versions = Object.keys(doc.versions || {});
      const installed = maxSatisfying(versions, range) || range.replace(/^[\^~]/, '');
      const installedManifest = doc.versions?.[installed] || {};
      const latest = doc['dist-tags']?.latest || null;
      const lastModified = doc.time?.modified || null;
      const deprecatedMsg = installedManifest.deprecated || doc.versions?.[latest]?.deprecated || null;
      const unpackedSize = installedManifest.dist?.unpackedSize ?? null;
      const license = installedManifest.license || doc.license || 'unknown';
      const readmeLen = (doc.readme || '').trim().length;
      // npm's registry API omits `readme` entirely for many high-traffic packages
      // (e.g. express, @angular/core) — a 0-length readme there does NOT mean
      // undocumented. Fall back to homepage/repository presence in that case.
      const homepage = installedManifest.homepage || doc.homepage || null;
      const repoUrl = (installedManifest.repository || doc.repository)?.url || null;
      const hasExternalDocLink = Boolean(homepage || repoUrl);

      // Health: deprecated OR >2 years since last publish (team's own npm-pachages.sh threshold)
      const twoYearsAgoMs = Date.now() - 2 * 365 * 24 * 60 * 60 * 1000;
      const lastModMs = lastModified ? Date.parse(lastModified) : null;
      const olderThan2y = lastModMs ? lastModMs < twoYearsAgoMs : null;
      const healthOk = !deprecatedMsg && olderThan2y === false;

      // Dockerfile-compatible latest: walk versions newest->oldest, first whose engines.node
      // floor <= dockerNodeMajor (or has no engines constraint at all)
      let dockerCompat = 'N/A';
      if (dockerNodeMajor !== 'NA') {
        const sorted = versions
          .filter((v) => !v.includes('-')) // exclude prereleases (alpha/beta/rc) — not real "latest"
          .map((v) => [v, parseVersion(v)])
          .filter(([, p]) => p)
          .sort((a, b) => cmp(b[1], a[1]));
        const majorNode = Number(dockerNodeMajor);
        for (const [v] of sorted) {
          const floor = engineFloor(doc.versions[v]?.engines);
          if (floor === null || floor <= majorNode) { dockerCompat = v; break; }
        }
      }

      const description = installedManifest.description || doc.description || '';
      const osv = await osvQuery(name, installed);
      const cveOk = SEV_RANK[osv.maxSeverity] < SEV_RANK.HIGH; // not compliant if any CVE >= HIGH

      rows.push({
        name,
        description,
        range,
        installed,
        minVersionOk: parseVersion(installed) ? parseVersion(installed)[0] >= 1 : false,
        healthOk,
        cveOk,
        cveCount: osv.count,
        cveMaxSeverity: osv.maxSeverity,
        cveWorst: osv.worst,
        cveBySeverity: osv.bySeverity,
        deprecatedMsg,
        lastModified,
        olderThan2y,
        readmeLen,
        hasExternalDocLink,
        docOk: readmeLen > 300 || (readmeLen === 0 && hasExternalDocLink),
        unpackedSize,
        license,
        latest,
        dockerCompat,
      });
      process.stderr.write(`ok: ${name}\n`);
    } catch (e) {
      rows.push({ name, range, error: String(e) });
      process.stderr.write(`ERROR: ${name}: ${e}\n`);
    }
    await new Promise((r) => setTimeout(r, 150)); // be polite to the registry
  }

  writeFileSync(
    `/home/dpaniagua/Documentos/git/bots/operations/events/20260910_dependency_best_practices_policy/data/npm_compliance_${label}.json`,
    JSON.stringify(rows, null, 2)
  );
  console.log(`done: ${label} — ${rows.length} packages`);
}

main();
