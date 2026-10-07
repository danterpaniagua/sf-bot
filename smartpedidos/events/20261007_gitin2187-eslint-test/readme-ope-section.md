# Borrador — sección "ope / Documentación" para los README de Platform, Concentrador y Backoffice

Estado: borrador, no aplicado a ningún repositorio. Los clones locales de Platform y Concentrador en `smartpedidos/repo/` son de solo lectura, y el repositorio de Backoffice no está clonado localmente. Para aplicarlo hay que hacerlo en cada repositorio (rama `ope`).

Estado actual de los README (lectura local): Platform `README.md` contiene solo ` # test 1`; Concentrador usa `Readme.md` (nombre con otra capitalización) con `#  Hola mundo`; Backoffice no se vio.

Valores para los badges: servidor `https://sfcg-sonarqube.smartfran.com`, `<TOKEN_BADGE>` es el token de badge que se obtiene en SonarQube (proyecto → Información → badges). No se escribe el token real en este archivo ni en el repositorio de pipelines; si el repositorio de la aplicación es privado, igual conviene confirmar con el equipo si el token puede quedar en el README.

---

## BLOQUE PLATFORM (`README.md`)

```markdown
# platforms-service

Servicio de integración con plataformas de delivery (SmartPedidos).

## Operaciones — Documentación

### Ejecutar el contenedor en local

Requisitos: Docker. El servicio necesita MongoDB y credenciales de AWS (SQS/SSM) accesibles; la configuración de cada ambiente está en `api/src/config/env/<NODE_ENV>.js`.

1. Construir la imagen (desde la raíz del repo):

   docker build -f api/Dockerfile -t platforms-service:local ./api

2. Ejecutarla (el puerto por defecto es `3087`, configurable con `NODE_PORT`):

   docker run --rm -p 3087:3087 -e NODE_ENV=development platforms-service:local

   El `ENTRYPOINT` es `npm run` y el `CMD` por defecto es `serve` (`node dist/index.js`). Para otro ambiente se puede pasar `serve:tst`, `serve:stg` o `serve:prd` como comando, o fijar `NODE_ENV`.

3. Credenciales de AWS: el script de desarrollo sin contenedor usa el perfil `smartfran` (`npm run start:dev`). Dentro del contenedor hay que pasar las credenciales como variables de entorno (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`) o montar `~/.aws` en modo lectura. Nunca se guardan credenciales en la imagen ni en este repositorio.

> Pendiente de validar: la secuencia anterior se armó leyendo el `Dockerfile`, `package.json` y la configuración; no se ejecutó.

### Calidad

Los pipelines de Jenkins ejecutan ESLint y SonarQube en cada build (ver el repositorio de pipelines).

---

[![Quality Gate Status](https://sfcg-sonarqube.smartfran.com/api/project_badges/measure?project=DEVELOP.SmartPedidos.Platform&metric=alert_status&token=<TOKEN_BADGE>)](https://sfcg-sonarqube.smartfran.com/dashboard?id=DEVELOP.SmartPedidos.Platform)
[![Bugs](https://sfcg-sonarqube.smartfran.com/api/project_badges/measure?project=DEVELOP.SmartPedidos.Platform&metric=bugs&token=<TOKEN_BADGE>)](https://sfcg-sonarqube.smartfran.com/dashboard?id=DEVELOP.SmartPedidos.Platform)
[![Vulnerabilities](https://sfcg-sonarqube.smartfran.com/api/project_badges/measure?project=DEVELOP.SmartPedidos.Platform&metric=vulnerabilities&token=<TOKEN_BADGE>)](https://sfcg-sonarqube.smartfran.com/dashboard?id=DEVELOP.SmartPedidos.Platform)
[![Code Smells](https://sfcg-sonarqube.smartfran.com/api/project_badges/measure?project=DEVELOP.SmartPedidos.Platform&metric=code_smells&token=<TOKEN_BADGE>)](https://sfcg-sonarqube.smartfran.com/dashboard?id=DEVELOP.SmartPedidos.Platform)
[![Technical Debt](https://sfcg-sonarqube.smartfran.com/api/project_badges/measure?project=DEVELOP.SmartPedidos.Platform&metric=sqale_index&token=<TOKEN_BADGE>)](https://sfcg-sonarqube.smartfran.com/dashboard?id=DEVELOP.SmartPedidos.Platform)
```

## BLOQUE CONCENTRADOR (`Readme.md`)

Igual que Platform, con estos cambios:

| Campo | Valor |
|---|---|
| Título | `concentrador-service` |
| Imagen | `concentrador-service:local` |
| Puerto por defecto | `3086` (`NODE_PORT`) |
| Dependencias | MongoDB; credenciales de AWS (no verificado qué servicios de AWS usa además de lo que figura en la configuración) |
| Perfil AWS del script de desarrollo | `smartfran` (`npm run start:dev`) |
| Proyecto SonarQube | `DEVELOP.SmartPedidos.Concentrador` |

Comando de `docker run`: `docker run --rm -p 3086:3086 -e NODE_ENV=development concentrador-service:local`. El `Dockerfile` de Concentrador no instala los certificados de `bot-security.smartfran.com` que sí instala el de Platform.

Badges: mismos cinco, con `project=DEVELOP.SmartPedidos.Concentrador` y su token de badge.

## BLOQUE BACKOFFICE (`README.md`)

Repositorio no clonado localmente, por lo que no se pudo leer su `Dockerfile`, `package.json` ni README. Lo único conocido: el código está en `app/` (según el pipeline) y el proyecto SonarQube es `DEVELOP.SmartPedidos.BackOffice`.

Pendiente de completar a partir del repositorio: comando de build (`docker build -f app/Dockerfile ...`, ruta a confirmar), puerto expuesto, variables de entorno necesarias y cómo se sirve (si es frontend estático detrás de un servidor web). Badges: los mismos cinco con `project=DEVELOP.SmartPedidos.BackOffice`.
