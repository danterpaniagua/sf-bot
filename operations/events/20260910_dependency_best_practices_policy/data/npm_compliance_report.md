# Reporte de cumplimiento npm — SmartPedidos (GITIN-2026)

Generado 2026-09-11 vía /sp-npm-compliance, sobre `develop` (rama productiva), fetch+ff-only aplicado antes de leer.

## Axiomas de cumplimiento

```
1. Versión mínima     >= 1.0.0, salvo excepción justificada
2. Salud del paquete   Deprecado o sin publicar hace más de 2 años (umbral propio
                       ya usado en sf-devops/.../npm-pachages.sh)
3. Documentación       README sustancial (>300 caracteres) o, si el registry no lo
                       expone (paquetes de alto tráfico como express/@angular/core
                       lo omiten), presencia de homepage/repository
4. Tamaño              dist.unpackedSize (npm registry) — proyectos backend, corren
                       en contenedor; bundlephobia para backOffice ya cubierto en
                       el email, no repetido acá
5. Licencia            Debe permitir uso comercial sin costo adicional
6. Última versión      Instalada (rango resuelto, sin package-lock.json real) vs.
                       última global vs. última compatible con Node del Dockerfile
                       real de develop (N/A para backOffice, sin runtime)
7. CVEs de la librería No compliant si CVE >= HIGH para la versión instalada
                       específicamente (consulta en vivo a OSV.dev)
```

## backOffice (Angular, S3+CloudFront — sin runtime, eje 6 N/A)

28 dependencias directas.

| Paquete | Descripción | Instalada | Ver.Mín | Salud | Global | Doc | Tamaño | Compat.Dockerfile | Licencia | CVEs |
|---|---|---|---|---|---|---|---|---|---|---|
| @angular/animations | Angular - animations integration with web-animations | 21.2.23 (rango: `~21.2.10`) | ✓ | ✗ @angular/animations is deprecated. Use `animate.enter` and `animate.leave` instead. For more information see: https://v22.angular.dev/guide/animations. | 22.1.6 | ✓ | 751.1 KB | N/A | MIT | ✓ (0) |
| @angular/platform-browser-dynamic | Angular - library for using Angular in a web browser with JIT compilation | 21.2.23 (rango: `~21.2.10`) | ✓ | ✗ @angular/platform-browser-dynamic is deprecated. Use `@angular/platform-browser` instead. | 22.1.6 | ✓ | 23.1 KB | N/A | MIT | ✓ (0) |
| bootstrap | The most popular front-end framework for developing responsive, mobile first projects on the web. | 4.3.1 (rango: `~4.3.1`) | ✓ | ✗ This version of Bootstrap is no longer supported. Please upgrade to the latest version. | 5.3.8 | ✓ | 4.37 MB | N/A | MIT | ✓ (0) |
| flat | Take a nested Javascript object and flatten it, or unflatten an object with delimited keys | 5.0.2 (rango: `~5.0.0`) | ✓ | ✗ Sin publicar hace más de 2 años (última: 2023-09-19) | 6.0.1 | ✓ | 26.6 KB | N/A | BSD-3-Clause | ✓ (0) |
| jquery | JavaScript library for DOM operations | 3.4.1 (rango: `3.4.1`) | ✓ | ✗ This version is deprecated. Please upgrade to the latest version or find support at https://www.herodevs.com/support/jquery-nes. | 4.0.0 | ✓ | 1.30 MB | N/A | MIT | ✓ 2 MODERATE (2 total) |
| moment | Parse, validate, manipulate, and display dates | 2.24.0 (rango: `2.24.0`) | ✓ | ✓ | 2.30.1 | ✓ | 2.79 MB | N/A | MIT | ✗ 2 HIGH (2 total) |
| popper.js | A kickass library to manage your poppers | 1.16.1-lts (rango: `~1.16.1`) | ✓ | ✗ You can find the new Popper v2 at @popperjs/core, this package is dedicated to the legacy v1 | 1.16.1 | ✓ | 1.72 MB | N/A | MIT | ✓ (0) |
| querystring | Node's querystring module for all engines. | 0.2.1 (rango: `~0.2.1`) | ✗ | ✗ The querystring API is considered Legacy. new code should use the URLSearchParams API instead. | 0.2.1 | ✓ | 9.4 KB | N/A | MIT | ✓ (0) |
| xlsx | SheetJS Spreadsheet data parser and writer | 0.15.6 (rango: `~0.15.3`) | ✗ | ✓ | 0.18.5 | ✓ | 8.68 MB | N/A | Apache-2.0 | ✗ 2 HIGH, 3 MODERATE (5 total) |
| @angular/cdk | Angular Material Component Development Kit | 20.2.14 (rango: `~20.2.0`) | ✓ | ✓ | 22.1.6 | ✓ | 4.82 MB | N/A | MIT | ✓ (0) |
| @angular/common | Angular - commonly needed directives and services | 21.2.23 (rango: `~21.2.10`) | ✓ | ✓ | 22.1.6 | ✓ | 9.53 MB | N/A | MIT | ✓ (0) |
| @angular/compiler | Angular - the compiler library | 21.2.23 (rango: `~21.2.10`) | ✓ | ✓ | 22.1.6 | ✓ | 4.43 MB | N/A | MIT | ✓ (0) |
| @angular/compiler-cli | Angular - the compiler CLI for Node.js | 21.2.23 (rango: `~21.2.10`) | ✓ | ✓ | 22.1.6 | ✓ | 2.87 MB | N/A | MIT | ✓ (0) |
| @angular/core | Angular - the core framework | 21.2.23 (rango: `~21.2.10`) | ✓ | ✓ | 22.1.6 | ✓ | 6.82 MB | N/A | MIT | ✓ (0) |
| @angular/forms | Angular - directives and services for creating forms | 21.2.23 (rango: `~21.2.10`) | ✓ | ✓ | 22.1.6 | ✓ | 1.59 MB | N/A | MIT | ✓ (0) |
| @angular/language-service | Angular - language services | 21.2.23 (rango: `~21.2.10`) | ✓ | ✓ | 22.1.6 | ✓ | 13.75 MB | N/A | MIT | ✓ (0) |
| @angular/material | Angular Material | 20.2.14 (rango: `~20.2.0`) | ✓ | ✓ | 22.1.6 | ✓ | 8.56 MB | N/A | MIT | ✓ (0) |
| @angular/platform-browser | Angular - library for using Angular in a web browser | 21.2.23 (rango: `~21.2.10`) | ✓ | ✓ | 22.1.6 | ✓ | 342.3 KB | N/A | MIT | ✓ (0) |
| @angular/router | Angular - the routing library | 21.2.23 (rango: `~21.2.10`) | ✓ | ✓ | 22.1.6 | ✓ | 1.22 MB | N/A | MIT | ✓ (0) |
| @fortawesome/fontawesome-free | The iconic font, CSS, and SVG framework | 5.11.2 (rango: `~5.11.2`) | ✓ | ✓ | 7.3.1 | ✓ | 10.64 MB | N/A | (CC-BY-4.0 AND OFL-1.1 AND MIT) | ✓ (0) |
| @sweetalert2/ngx-sweetalert2 |  | 14.1.4 (rango: `~14.1.4`) | ✓ | ✓ | 15.0.0 | ✗ (readme 28c, link ext.: true) | 144.9 KB | N/A | unknown | ✓ (0) |
| apexcharts | A JavaScript Chart Library | 5.10.6 (rango: `~5.10.6`) | ✓ | ✓ | 7.1.0 | ✓ | 9.05 MB | N/A | SEE LICENSE IN LICENSE | ✓ (0) |
| ng-apexcharts | An angular implementation of ApexCharts | 2.4.0 (rango: `~2.4.0`) | ✓ | ✓ | 3.1.0 | ✓ | 147.0 KB | N/A | unknown | ✓ (0) |
| ngx-spinner | A library with more than 50 different loading spinners for Angular 4 - 21. (https://napster2210.github.io/ngx-spinner/) | 21.1.0 (rango: `~21.1.0`) | ✓ | ✓ | 22.0.1 | ✓ | 185.2 KB | N/A | MIT | ✓ (0) |
| rxjs | Reactive Extensions for modern JavaScript | 7.8.2 (rango: `~7.8.2`) | ✓ | ✓ | 7.8.2 | ✓ | 4.50 MB | N/A | Apache-2.0 | ✓ (0) |
| sweetalert2 | A beautiful, responsive, customizable and accessible (WAI-ARIA) replacement for JavaScript's popup boxes, supported fork of sweetalert | 11.26.25 (rango: `~11.26.24`) | ✓ | ✓ | 11.26.25 | ✓ | 1.22 MB | N/A | MIT | ✓ (0) |
| tslib | Runtime library for TypeScript helper functions | 1.9.3 (rango: `~1.9.0`) | ✓ | ✓ | 2.8.1 | ✓ | 58.4 KB | N/A | Apache-2.0 | ✓ (0) |
| zone.js | Zones for JavaScript | 0.15.1 (rango: `~0.15.1`) | ✗ | ✓ | 0.16.3 | ✓ | 2.10 MB | N/A | MIT | ✓ (0) |

## platformsService (ECS/Fargate, Node 20.20-alpine)

34 dependencias directas.

| Paquete | Descripción | Instalada | Ver.Mín | Salud | Global | Doc | Tamaño | Compat.Dockerfile | Licencia | CVEs |
|---|---|---|---|---|---|---|---|---|---|---|
| @types/form-data | Stub TypeScript definitions entry for form-data, which provides its own types definitions | 2.5.2 (rango: `^2.5.2`) | ✓ | ✗ This is a stub types definition. form-data provides its own type definitions, so you do not need this installed. | 2.5.2 | ✗ (readme 15c, link ext.: false) | 1.7 KB | 2.5.2 | MIT | ✓ (0) |
| axios | Promise based HTTP client for the browser and node.js | 1.13.6 (rango: `~1.13.5`) | ✓ | ✓ | 1.20.0 | ✓ | 2.42 MB | 1.20.0 | MIT | ✗ 10 HIGH, 17 MODERATE, 1 LOW (28 total) |
| env-var | Verification, sanitization, and type coercion for environment variables in Node.js | 7.5.0 (rango: `^7.5.0`) | ✓ | ✗ Sin publicar hace más de 2 años (última: 2024-05-20) | 7.5.0 | ✓ | 42.9 KB | 7.5.0 | MIT | ✓ (0) |
| express-jwt | JWT authentication middleware. | 5.3.3 (rango: `^5.3.1`) | ✓ | ✓ | 8.5.1 | ✓ | 42.2 KB | 8.5.1 | MIT | ✗ 1 HIGH (1 total) |
| jsonwebtoken | JSON Web Token implementation (symmetric and asymmetric) | 8.5.1 (rango: `^8.3.0`) | ✓ | ✓ | 9.0.3 | ✓ | 73.9 KB | 9.0.3 | MIT | ✗ 1 HIGH, 2 MODERATE (3 total) |
| regenerator-runtime | Runtime for Regenerator-compiled generator and async functions. | 0.13.11 (rango: `^0.13.3`) | ✗ | ✗ Sin publicar hace más de 2 años (última: 2023-12-15) | 0.14.1 | ✓ | 27.8 KB | 0.14.1 | MIT | ✓ (0) |
| swagger-ui-express | Swagger UI Express | 5.0.1 (rango: `^5.0.0`) | ✓ | ✗ Sin publicar hace más de 2 años (última: 2024-05-31) | 5.0.1 | ✓ | 24.0 KB | 5.0.1 | MIT | ✓ (0) |
| uuid | RFC4122 (v1, v4, and v5) UUIDs | 8.0.0 (rango: `8.0.0`) | ✓ | ✗ uuid@10 and below is no longer supported.  For ESM codebases, update to uuid@latest.  For CommonJS codebases, use uuid@11 (but be aware this version will likely be deprecated in 2028). | 14.0.2 | ✓ | 93.0 KB | 14.0.2 | MIT | ✓ 1 MODERATE (1 total) |
| @aws-sdk/client-sqs | AWS SDK for JavaScript Sqs Client for Node.js, Browser and React Native | 3.1130.0 (rango: `^3.0.0`) | ✓ | ✓ | 3.1130.0 | ✓ | 619.3 KB | 3.1130.0 | Apache-2.0 | ✓ (0) |
| @aws-sdk/client-ssm | AWS SDK for JavaScript Ssm Client for Node.js, Browser and React Native | 3.1130.0 (rango: `^3.0.0`) | ✓ | ✓ | 3.1130.0 | ✓ | 3.45 MB | 3.1130.0 | Apache-2.0 | ✓ (0) |
| @babel/core | Babel compiler core. | 7.29.7 (rango: `^7.27.0`) | ✓ | ✓ | 8.0.5 | ✓ | 810.6 KB | 7.29.7 | MIT | ✓ (0) |
| @babel/node | Babel command line | 7.29.7 (rango: `^7.27.0`) | ✓ | ✓ | 8.0.5 | ✓ | 54.3 KB | 7.29.7 | MIT | ✓ (0) |
| @babel/runtime | babel's modular runtime helpers | 7.29.7 (rango: `^7.27.0`) | ✓ | ✓ | 8.0.5 | ✓ | 247.7 KB | 8.0.5 | MIT | ✓ (0) |
| @meanie/mongoose-to-json | A plugin for Mongoose to normalize JSON output | 2.6.0 (rango: `^2.4.0`) | ✓ | ✓ | 2.6.0 | ✓ | 9.2 KB | 2.6.0 | MIT | ✓ (0) |
| @sendgrid/mail | Twilio SendGrid NodeJS mail service | 7.7.0 (rango: `^7.7.0`) | ✓ | ✓ | 8.1.6 | ✓ | 17.2 KB | 8.1.6 | MIT | ✓ (0) |
| body-parser | Node.js body parsing middleware | 1.20.8 (rango: `^1.18.3`) | ✓ | ✓ | 2.3.0 | ✓ | 60.8 KB | 2.3.0 | MIT | ✓ (0) |
| cookie-parser | Parse HTTP request cookies | 1.4.7 (rango: `^1.4.3`) | ✓ | ✓ | 1.4.7 | ✓ | 13.0 KB | 1.4.7 | MIT | ✓ (0) |
| core-js | Standard library | 3.50.0 (rango: `^3.2.1`) | ✓ | ✓ | 3.50.0 | ✓ | 1.36 MB | 3.50.0 | MIT | ✓ (0) |
| cors | Node.js CORS middleware | 2.8.6 (rango: `^2.8.5`) | ✓ | ✓ | 2.8.6 | ✓ | 20.0 KB | 2.8.6 | MIT | ✓ (0) |
| cross-env | Run scripts that set and use environment variables across platforms | 7.0.3 (rango: `^7.0.3`) | ✓ | ✓ | 10.1.0 | ✓ | 29.1 KB | 10.1.0 | MIT | ✓ (0) |
| express | Fast, unopinionated, minimalist web framework | 4.22.2 (rango: `^4.16.3`) | ✓ | ✓ | 5.2.1 | ✓ | 222.5 KB | 5.2.1 | MIT | ✓ (0) |
| form-data | A library to create readable "multipart/form-data" streams. Can be used to submit forms and file uploads to other web applications. | 4.0.6 (rango: `^4.0.2`) | ✓ | ✓ | 4.0.6 | ✓ | 83.9 KB | 4.0.6 | MIT | ✓ (0) |
| lodash | Lodash modular utilities. | 4.18.1 (rango: `^4.17.15`) | ✓ | ✓ | 4.18.1 | ✓ | 1.41 MB | 4.18.1 | MIT | ✓ (0) |
| moment | Parse, validate, manipulate, and display dates | 2.30.1 (rango: `^2.22.2`) | ✓ | ✓ | 2.30.1 | ✓ | 4.35 MB | 2.30.1 | MIT | ✓ (0) |
| mongoose | Mongoose MongoDB ODM | 7.8.12 (rango: `~7.8.7`) | ✓ | ✓ | 9.10.0 | ✓ | 2.63 MB | 9.10.0 | MIT | ✓ (0) |
| mongoose-unique-validator | mongoose-unique-validator is a plugin which adds pre-save validation for unique fields within a Mongoose schema. | 4.0.1 (rango: `~4.0.1`) | ✓ | ✓ | 6.1.1 | ✓ | 16.0 KB | 5.0.2 | MIT | ✓ (0) |
| morgan | HTTP request logger middleware for node.js | 1.12.1 (rango: `^1.9.1`) | ✓ | ✓ | 1.12.1 | ✓ | 27.8 KB | 1.12.1 | MIT | ✓ (0) |
| node-cron | A simple cron-like task scheduler for Node.js | 2.0.3 (rango: `^2.0.3`) | ✓ | ✓ | 4.6.0 | ✓ | 63.4 KB | 4.6.0 | ISC | ✓ (0) |
| node-schedule | A cron-like and not-cron-like job scheduler for Node. | 2.1.1 (rango: `^2.0.0`) | ✓ | ✓ | 2.1.1 | ✓ | 35.0 KB | 2.1.1 | MIT | ✓ (0) |
| nodemon | Simple monitor script for use during development of a node.js app. | 1.19.4 (rango: `^1.18.4`) | ✓ | ✓ | 3.1.14 | ✓ | 104.7 KB | 3.1.14 | MIT | ✓ (0) |
| sqs-consumer | Build SQS-based Node applications without the boilerplate | 11.6.0 (rango: `^11.0.0`) | ✓ | ✓ | 15.0.3 | ✓ | 150.4 KB | 15.0.0 | Apache-2.0 | ✓ (0) |
| swagger-jsdoc | Generates swagger doc based on JSDoc | 6.3.0 (rango: `^6.2.8`) | ✓ | ✓ | 6.3.0 | ✓ | 710.0 KB | 6.3.0 | MIT | ✓ (0) |
| winston | A logger for just about everything. | 3.2.1 (rango: `3.2.1`) | ✓ | ✓ | 3.19.0 | ✓ | 305.1 KB | 3.19.0 | MIT | ✓ (0) |
| winston-mongodb | A MongoDB transport for winston | 5.0.0 (rango: `5.0.0`) | ✓ | ✓ | 7.0.1 | ✓ | 26.5 KB | 7.0.1 | MIT | ✓ (0) |

## concentradorService (ECS/Fargate, Node 20.20-alpine)

28 dependencias directas.

| Paquete | Descripción | Instalada | Ver.Mín | Salud | Global | Doc | Tamaño | Compat.Dockerfile | Licencia | CVEs |
|---|---|---|---|---|---|---|---|---|---|---|
| axios | Promise based HTTP client for the browser and node.js | 1.13.6 (rango: `~1.13.5`) | ✓ | ✓ | 1.20.0 | ✓ | 2.42 MB | 1.20.0 | MIT | ✗ 10 HIGH, 17 MODERATE, 1 LOW (28 total) |
| crypto-js | JavaScript library of crypto standards. | 4.2.0 (rango: `^4.2.0`) | ✓ | ✗ Active development of CryptoJS has been discontinued. This library is no longer maintained. | 4.2.0 | ✓ | 486.9 KB | 4.2.0 | MIT | ✓ (0) |
| regenerator-runtime | Runtime for Regenerator-compiled generator and async functions. | 0.13.11 (rango: `^0.13.3`) | ✗ | ✗ Sin publicar hace más de 2 años (última: 2023-12-15) | 0.14.1 | ✓ | 27.8 KB | 0.14.1 | MIT | ✓ (0) |
| swagger-ui-express | Swagger UI Express | 5.0.1 (rango: `^5.0.0`) | ✓ | ✗ Sin publicar hace más de 2 años (última: 2024-05-31) | 5.0.1 | ✓ | 24.0 KB | 5.0.1 | MIT | ✓ (0) |
| uuid | RFC4122 (v1, v4, and v5) UUIDs | 8.0.0 (rango: `8.0.0`) | ✓ | ✗ uuid@10 and below is no longer supported.  For ESM codebases, update to uuid@latest.  For CommonJS codebases, use uuid@11 (but be aware this version will likely be deprecated in 2028). | 14.0.2 | ✓ | 93.0 KB | 14.0.2 | MIT | ✓ 1 MODERATE (1 total) |
| @aws-sdk/client-sqs | AWS SDK for JavaScript Sqs Client for Node.js, Browser and React Native | 3.1130.0 (rango: `^3.0.0`) | ✓ | ✓ | 3.1130.0 | ✓ | 619.3 KB | 3.1130.0 | Apache-2.0 | ✓ (0) |
| @aws-sdk/client-ssm | AWS SDK for JavaScript Ssm Client for Node.js, Browser and React Native | 3.1130.0 (rango: `^3.0.0`) | ✓ | ✓ | 3.1130.0 | ✓ | 3.45 MB | 3.1130.0 | Apache-2.0 | ✓ (0) |
| @babel/core | Babel compiler core. | 7.29.7 (rango: `^7.6.0`) | ✓ | ✓ | 8.0.5 | ✓ | 810.6 KB | 7.29.7 | MIT | ✓ (0) |
| @babel/runtime | babel's modular runtime helpers | 7.29.7 (rango: `^7.27.6`) | ✓ | ✓ | 8.0.5 | ✓ | 247.7 KB | 8.0.5 | MIT | ✓ (0) |
| @meanie/mongoose-to-json | A plugin for Mongoose to normalize JSON output | 2.6.0 (rango: `^2.4.0`) | ✓ | ✓ | 2.6.0 | ✓ | 9.2 KB | 2.6.0 | MIT | ✓ (0) |
| @sendgrid/mail | Twilio SendGrid NodeJS mail service | 7.7.0 (rango: `^7.7.0`) | ✓ | ✓ | 8.1.6 | ✓ | 17.2 KB | 8.1.6 | MIT | ✓ (0) |
| body-parser | Node.js body parsing middleware | 1.20.8 (rango: `^1.18.3`) | ✓ | ✓ | 2.3.0 | ✓ | 60.8 KB | 2.3.0 | MIT | ✓ (0) |
| cookie-parser | Parse HTTP request cookies | 1.4.7 (rango: `^1.4.3`) | ✓ | ✓ | 1.4.7 | ✓ | 13.0 KB | 1.4.7 | MIT | ✓ (0) |
| core-js | Standard library | 3.50.0 (rango: `^3.2.1`) | ✓ | ✓ | 3.50.0 | ✓ | 1.36 MB | 3.50.0 | MIT | ✓ (0) |
| cors | Node.js CORS middleware | 2.8.6 (rango: `^2.8.5`) | ✓ | ✓ | 2.8.6 | ✓ | 20.0 KB | 2.8.6 | MIT | ✓ (0) |
| express | Fast, unopinionated, minimalist web framework | 4.22.2 (rango: `^4.18.2`) | ✓ | ✓ | 5.2.1 | ✓ | 222.5 KB | 5.2.1 | MIT | ✓ (0) |
| express-jwt | JWT authentication middleware. | 8.5.1 (rango: `^8.5.1`) | ✓ | ✓ | 8.5.1 | ✓ | 28.5 KB | 8.5.1 | MIT | ✓ (0) |
| form-data | A library to create readable "multipart/form-data" streams. Can be used to submit forms and file uploads to other web applications. | 4.0.6 (rango: `^4.0.2`) | ✓ | ✓ | 4.0.6 | ✓ | 83.9 KB | 4.0.6 | MIT | ✓ (0) |
| jsonwebtoken | JSON Web Token implementation (symmetric and asymmetric) | 9.0.3 (rango: `^9.0.3`) | ✓ | ✓ | 9.0.3 | ✓ | 43.4 KB | 9.0.3 | MIT | ✓ (0) |
| lodash | Lodash modular utilities. | 4.18.1 (rango: `^4.17.15`) | ✓ | ✓ | 4.18.1 | ✓ | 1.41 MB | 4.18.1 | MIT | ✓ (0) |
| moment | Parse, validate, manipulate, and display dates | 2.30.1 (rango: `^2.22.2`) | ✓ | ✓ | 2.30.1 | ✓ | 4.35 MB | 2.30.1 | MIT | ✓ (0) |
| mongoose | Mongoose MongoDB ODM | 7.8.12 (rango: `~7.8.7`) | ✓ | ✓ | 9.10.0 | ✓ | 2.63 MB | 9.10.0 | MIT | ✓ (0) |
| mongoose-unique-validator | mongoose-unique-validator is a plugin which adds pre-save validation for unique fields within a Mongoose schema. | 4.0.1 (rango: `~4.0.1`) | ✓ | ✓ | 6.1.1 | ✓ | 16.0 KB | 5.0.2 | MIT | ✓ (0) |
| morgan | HTTP request logger middleware for node.js | 1.12.1 (rango: `^1.9.1`) | ✓ | ✓ | 1.12.1 | ✓ | 27.8 KB | 1.12.1 | MIT | ✓ (0) |
| node-cron | A simple cron-like task scheduler for Node.js | 2.0.3 (rango: `^2.0.3`) | ✓ | ✓ | 4.6.0 | ✓ | 63.4 KB | 4.6.0 | ISC | ✓ (0) |
| swagger-jsdoc | Generates swagger doc based on JSDoc | 6.3.0 (rango: `^6.2.8`) | ✓ | ✓ | 6.3.0 | ✓ | 710.0 KB | 6.3.0 | MIT | ✓ (0) |
| winston | A logger for just about everything. | 3.2.1 (rango: `3.2.1`) | ✓ | ✓ | 3.19.0 | ✓ | 305.1 KB | 3.19.0 | MIT | ✓ (0) |
| winston-mongodb | A MongoDB transport for winston | 5.0.0 (rango: `5.0.0`) | ✓ | ✓ | 7.0.1 | ✓ | 26.5 KB | 7.0.1 | MIT | ✓ (0) |

