#!/usr/bin/env node
// NuGet dependency compliance check — see .claude/commands/cloud-nuget-compliance.md
// Usage: node nuget_compliance_check.mjs <packages.txt: "Name Version" per line> <label>

import { readFileSync, writeFileSync } from 'fs';

const [, , listPath, label] = process.argv;

function xmlField(xml, tag) {
  const m = new RegExp(`<d:${tag}[^>]*>([^<]*)</d:${tag}>`).exec(xml);
  return m ? m[1] : null;
}
function xmlFieldNull(xml, tag) {
  // self-closing m:null="true" fields
  return new RegExp(`<d:${tag}[^>]*m:null="true"`).test(xml);
}

function parseVersion(v) {
  const m = /^(\d+)\.(\d+)\.(\d+)/.exec(v);
  if (!m) return null;
  return [Number(m[1]), Number(m[2]), Number(m[3])];
}
function cmp(a, b) {
  for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] - b[i];
  return 0;
}

async function fetchV2(name, version) {
  const url = `https://www.nuget.org/api/v2/Packages(Id='${encodeURIComponent(name)}',Version='${encodeURIComponent(version)}')`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`V2 ${name}@${version}: HTTP ${res.status}`);
  const xml = await res.text();
  return {
    description: xmlField(xml, 'Description') || '',
    projectUrl: xmlFieldNull(xml, 'ProjectUrl') ? null : xmlField(xml, 'ProjectUrl'),
    licenseUrl: xmlFieldNull(xml, 'LicenseUrl') ? null : xmlField(xml, 'LicenseUrl'),
    licenseNames: xmlField(xml, 'LicenseNames'),
    published: xmlField(xml, 'Published'),
    packageSize: Number(xmlField(xml, 'PackageSize') || 0),
    listed: xmlField(xml, 'IsLatestVersion'),
  };
}

async function fetchAllVersions(name) {
  const res = await fetch(`https://api.nuget.org/v3-flatcontainer/${name.toLowerCase()}/index.json`);
  if (!res.ok) return [];
  const data = await res.json();
  return data.versions || [];
}

async function fetchCatalogEntry(name, version) {
  // V3 registration index — paged. Find the page containing `version`, fetch it, read its catalogEntry
  // (deprecation + licenseExpression both live here; V2 OData's LicenseNames field is usually empty).
  try {
    const idxRes = await fetch(`https://api.nuget.org/v3/registration5-semver1/${name.toLowerCase()}/index.json`);
    if (!idxRes.ok) return {};
    const idx = await idxRes.json();
    const v = parseVersion(version);
    if (!v) return {};
    // Always find the page whose [lower, upper] bounds actually contain the target version —
    // a page having inline `.items` does NOT mean it's the only page or the right one.
    let page = idx.items?.find((p) => {
      const lo = parseVersion(p.lower), hi = parseVersion(p.upper);
      return lo && hi && cmp(v, lo) >= 0 && cmp(v, hi) <= 0;
    });
    if (!page && idx.items?.length === 1) page = idx.items[0]; // single unpaged package
    let pageItems = page?.items || null;
    if (!pageItems && page?.['@id']) {
      const pageRes = await fetch(page['@id']);
      if (pageRes.ok) pageItems = (await pageRes.json()).items;
    }
    const entry = pageItems?.find((it) => it.catalogEntry?.version === version)?.catalogEntry;
    return { deprecation: entry?.deprecation || null, licenseExpression: entry?.licenseExpression || null, licenseUrl: entry?.licenseUrl || null };
  } catch {
    return {};
  }
}

const SEV_RANK = { UNKNOWN: 0, LOW: 1, MODERATE: 2, HIGH: 3, CRITICAL: 4 };
async function osvQuery(name, version) {
  const res = await fetch('https://api.osv.dev/v1/query', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ package: { name, ecosystem: 'NuGet' }, version }),
  });
  if (!res.ok) return { count: 0, maxSeverity: 'UNKNOWN', worst: null, bySeverity: {} };
  const data = await res.json();
  const vulns = data.vulns || [];
  let maxSeverity = 'UNKNOWN', worst = null;
  const bySeverity = { CRITICAL: 0, HIGH: 0, MODERATE: 0, LOW: 0, UNKNOWN: 0 };
  for (const v of vulns) {
    const label = (v.database_specific?.severity || 'UNKNOWN').toUpperCase();
    bySeverity[label] = (bySeverity[label] ?? 0) + 1;
    if ((SEV_RANK[label] ?? 0) > (SEV_RANK[maxSeverity] ?? 0)) { maxSeverity = label; worst = { id: v.id, summary: v.summary }; }
  }
  return { count: vulns.length, maxSeverity, worst, bySeverity };
}

async function main() {
  const lines = readFileSync(listPath, 'utf8').trim().split('\n');
  const rows = [];

  for (const line of lines) {
    const m = /^(\S+)\s+(\S+)$/.exec(line.trim());
    if (!m) continue;
    let [, name, version] = m;
    try {
      if (version.includes('*')) {
        const all = await fetchAllVersions(name);
        const prefix = version.replace('*', '');
        const matches = all.filter((v) => v.startsWith(prefix) && !v.includes('-'));
        version = matches.sort((a, b) => cmp(parseVersion(a) || [0,0,0], parseVersion(b) || [0,0,0])).pop() || version;
      }

      const [v2, allVersions, catalogEntry, osv] = await Promise.all([
        fetchV2(name, version),
        fetchAllVersions(name),
        fetchCatalogEntry(name, version),
        osvQuery(name, version),
      ]);
      const { deprecation, licenseExpression, licenseUrl } = catalogEntry;

      const stableVersions = allVersions.filter((v) => !v.includes('-'));
      const latest = stableVersions.sort((a, b) => cmp(parseVersion(a) || [0,0,0], parseVersion(b) || [0,0,0])).pop() || null;

      const twoYearsAgoMs = Date.now() - 2 * 365 * 24 * 60 * 60 * 1000;
      const publishedMs = v2.published ? Date.parse(v2.published) : null;
      const olderThan2y = publishedMs ? publishedMs < twoYearsAgoMs : null;
      const healthOk = !deprecation && olderThan2y === false;

      const license = licenseExpression || (licenseUrl || v2.licenseUrl ? `URL (manual check): ${licenseUrl || v2.licenseUrl}` : 'unknown');
      const docOk = (v2.description || '').trim().length > 50 || Boolean(v2.projectUrl);
      const cveOk = SEV_RANK[osv.maxSeverity] < SEV_RANK.HIGH;

      rows.push({
        name, version, description: v2.description,
        minVersionOk: parseVersion(version) ? parseVersion(version)[0] >= 1 : false,
        healthOk, deprecation, publishedDate: v2.published, olderThan2y,
        docOk, projectUrl: v2.projectUrl,
        packageSize: v2.packageSize,
        latest,
        license,
        cveOk, cveCount: osv.count, cveMaxSeverity: osv.maxSeverity, cveBySeverity: osv.bySeverity, cveWorst: osv.worst,
      });
      process.stderr.write(`ok: ${name}@${version}\n`);
    } catch (e) {
      rows.push({ name, version, error: String(e) });
      process.stderr.write(`ERROR: ${name}@${version}: ${e}\n`);
    }
    await new Promise((r) => setTimeout(r, 150));
  }

  writeFileSync(
    `/home/dpaniagua/Documentos/git/bots/operations/events/20260910_dependency_best_practices_policy/data/nuget_compliance_${label}.json`,
    JSON.stringify(rows, null, 2)
  );
  console.log(`done: ${label} — ${rows.length} entries`);
}

main();
