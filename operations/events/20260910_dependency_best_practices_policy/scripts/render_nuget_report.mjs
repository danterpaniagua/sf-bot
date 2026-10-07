#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'fs';

const DATA_DIR = '/home/dpaniagua/Documentos/git/bots/operations/events/20260910_dependency_best_practices_policy/data';

function fmtSize(bytes) {
  if (!bytes) return '?';
  if (bytes > 1e6) return (bytes / 1e6).toFixed(2) + ' MB';
  return (bytes / 1e3).toFixed(1) + ' KB';
}
function healthReason(r) {
  if (r.deprecation) return `Deprecado: ${r.deprecation.message || JSON.stringify(r.deprecation)}`.slice(0, 200);
  if (r.olderThan2y) return `Sin publicar hace más de 2 años (última: ${r.publishedDate?.slice(0, 10)})`;
  return 'OK';
}
function cveCell(r) {
  if (!r.cveCount) return '✓ (0)';
  const bs = r.cveBySeverity || {};
  const parts = ['CRITICAL', 'HIGH', 'MODERATE', 'LOW'].filter((k) => bs[k]).map((k) => `${bs[k]} ${k}`);
  const mark = r.cveOk ? '✓' : '✗';
  return `${mark} ${parts.join(', ')} (${r.cveCount} total)`;
}

const rows = JSON.parse(readFileSync(`${DATA_DIR}/nuget_compliance_cloud.json`, 'utf8'));
const errors = rows.filter((r) => r.error);
const ok = rows.filter((r) => !r.error)
  .sort((a, b) => {
    const aBad = !a.healthOk || !a.cveOk || !a.minVersionOk, bBad = !b.healthOk || !b.cveOk || !b.minVersionOk;
    if (aBad !== bBad) return aBad ? -1 : 1;
    return a.name.localeCompare(b.name);
  });

let out = `# Reporte de cumplimiento NuGet — SmartFran Cloud (GITIN-2026)\n\n`;
out += `Generado 2026-09-11 vía /cloud-nuget-compliance, sobre \`main\` (rama productiva de Cloud — fast-forward aplicado antes de leer: estaba 156 commits atrás).\n\n`;
out += `## Axiomas de cumplimiento\n\n\`\`\`\n`;
out += `1. Versión mínima      >= 1.0.0, salvo excepción justificada\n`;
out += `2. Salud del paquete    Deprecado (catalogEntry.deprecation) o sin publicar hace\n`;
out += `                        más de 2 años (misma convención que /sp-npm-compliance)\n`;
out += `3. Documentación        Description sustancial (>50 caracteres) o ProjectUrl presente\n`;
out += `4. Tamaño               PackageSize (NuGet V2 OData, .nupkg completo)\n`;
out += `5. Licencia             licenseExpression (SPDX) si existe; si no, licenseUrl marcado\n`;
out += `                        para revisión manual (no asumir el contenido de una URL)\n`;
out += `6. Última versión       Instalada vs. última global. Eje "compatible con runtime"\n`;
out += `                        NO calculado acá — Cloud no tiene un único TargetFramework\n`;
out += `                        fleet-wide como el Node único de un Dockerfile; requiere\n`;
out += `                        especificar un proyecto puntual\n`;
out += `7. CVEs de la librería  No compliant si CVE >= HIGH para la versión instalada\n`;
out += `                        específicamente (consulta en vivo a OSV.dev, ecosystem NuGet)\n`;
out += `\`\`\`\n\n`;

if (errors.length) {
  out += `## Errores de resolución (reales, no del script)\n\n`;
  for (const e of errors) out += `- **${e.name}@${e.version}**: ${e.error}\n`;
  out += `\n`;
}

out += `## Todas las dependencias (${ok.length} entradas — nombre+versión únicos, no paquetes únicos; el mismo paquete puede aparecer varias veces con versiones distintas entre proyectos)\n\n`;
out += `| Paquete | Versión | Descripción | Ver.Mín | Salud | Global | Doc | Tamaño | Licencia | CVEs |\n`;
out += `|---|---|---|---|---|---|---|---|---|---|\n`;
for (const r of ok) {
  const minv = r.minVersionOk ? '✓' : '✗';
  const health = r.healthOk ? '✓' : `✗ ${healthReason(r)}`;
  const doc = r.docOk ? '✓' : '✗';
  const desc = (r.description || '').replace(/\|/g, '\\|').replace(/\n/g, ' ');
  out += `| ${r.name} | ${r.version} | ${desc} | ${minv} | ${health} | ${r.latest} | ${doc} | ${fmtSize(r.packageSize)} | ${r.license} | ${cveCell(r)} |\n`;
}

writeFileSync(`${DATA_DIR}/nuget_compliance_report.md`, out);
console.log('written');
