#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'fs';

const DATA_DIR = '/home/dpaniagua/Documentos/git/bots/operations/events/20260910_dependency_best_practices_policy/data';
const projects = [
  { file: 'npm_compliance_backoffice.json', label: 'backOffice (Angular, S3+CloudFront — sin runtime, eje 6 N/A)' },
  { file: 'npm_compliance_platforms.json', label: 'platformsService (ECS/Fargate, Node 20.20-alpine)' },
  { file: 'npm_compliance_concentrador.json', label: 'concentradorService (ECS/Fargate, Node 20.20-alpine)' },
];

function fmtSize(bytes) {
  if (bytes == null) return '?';
  if (bytes > 1e6) return (bytes / 1e6).toFixed(2) + ' MB';
  return (bytes / 1e3).toFixed(1) + ' KB';
}
function healthReason(r) {
  if (r.deprecatedMsg) return r.deprecatedMsg.slice(0, 200);
  if (r.olderThan2y) return `Sin publicar hace más de 2 años (última: ${r.lastModified?.slice(0, 10)})`;
  return 'OK';
}
function cveCell(r) {
  if (!r.cveCount) return '✓ (0)';
  const bs = r.cveBySeverity || {};
  const parts = ['CRITICAL', 'HIGH', 'MODERATE', 'LOW'].filter((k) => bs[k]).map((k) => `${bs[k]} ${k}`);
  const mark = r.cveOk ? '✓' : '✗';
  return `${mark} ${parts.join(', ')} (${r.cveCount} total)`;
}

let out = `# Reporte de cumplimiento npm — SmartPedidos (GITIN-2026)\n\n`;
out += `Generado 2026-09-11 vía /sp-npm-compliance, sobre \`develop\` (rama productiva), fetch+ff-only aplicado antes de leer.\n\n`;
out += `## Axiomas de cumplimiento\n\n\`\`\`\n`;
out += `1. Versión mínima     >= 1.0.0, salvo excepción justificada\n`;
out += `2. Salud del paquete   Deprecado o sin publicar hace más de 2 años (umbral propio\n`;
out += `                       ya usado en sf-devops/.../npm-pachages.sh)\n`;
out += `3. Documentación       README sustancial (>300 caracteres) o, si el registry no lo\n`;
out += `                       expone (paquetes de alto tráfico como express/@angular/core\n`;
out += `                       lo omiten), presencia de homepage/repository\n`;
out += `4. Tamaño              dist.unpackedSize (npm registry) — proyectos backend, corren\n`;
out += `                       en contenedor; bundlephobia para backOffice ya cubierto en\n`;
out += `                       el email, no repetido acá\n`;
out += `5. Licencia            Debe permitir uso comercial sin costo adicional\n`;
out += `6. Última versión      Instalada (rango resuelto, sin package-lock.json real) vs.\n`;
out += `                       última global vs. última compatible con Node del Dockerfile\n`;
out += `                       real de develop (N/A para backOffice, sin runtime)\n`;
out += `7. CVEs de la librería No compliant si CVE >= HIGH para la versión instalada\n`;
out += `                       específicamente (consulta en vivo a OSV.dev)\n`;
out += `\`\`\`\n\n`;

for (const { file, label } of projects) {
  const rows = JSON.parse(readFileSync(`${DATA_DIR}/${file}`, 'utf8'))
    .sort((a, b) => {
      // Unhealthy or CVE>=HIGH first, then alphabetical within each group
      const aBad = !a.healthOk || !a.cveOk, bBad = !b.healthOk || !b.cveOk;
      if (aBad !== bBad) return aBad ? -1 : 1;
      return a.name.localeCompare(b.name);
    });
  out += `## ${label}\n\n`;
  out += `${rows.length} dependencias directas.\n\n`;
  out += `| Paquete | Descripción | Instalada | Ver.Mín | Salud | Global | Doc | Tamaño | Compat.Dockerfile | Licencia | CVEs |\n`;
  out += `|---|---|---|---|---|---|---|---|---|---|---|\n`;
  for (const r of rows) {
    const minv = r.minVersionOk ? '✓' : '✗';
    const health = r.healthOk ? '✓' : `✗ ${healthReason(r)}`;
    const doc = r.docOk ? '✓' : `✗ (readme ${r.readmeLen}c, link ext.: ${r.hasExternalDocLink})`;
    const desc = (r.description || '').replace(/\|/g, '\\|');
    out += `| ${r.name} | ${desc} | ${r.installed} (rango: \`${r.range}\`) | ${minv} | ${health} | ${r.latest} | ${doc} | ${fmtSize(r.unpackedSize)} | ${r.dockerCompat} | ${r.license} | ${cveCell(r)} |\n`;
  }
  out += `\n`;
}

writeFileSync(`${DATA_DIR}/npm_compliance_report.md`, out);
console.log('written');
