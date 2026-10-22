#!/usr/bin/env python3
"""Adds one sub-row per task (N.a, N.b, ...; letters because Excel turns 1.1 into a date) under stories 2 to 12 of outputs/tabla-roadmap.md.

Source of the tasks and their Proyecto / Ticket / Dev requirement: the "Detalle por Story" tables of outputs/roadmap-smartpedidos.md.
Sub-rows carry the priority of their story and no estimate of their own ("Incluida en la fila N"), so the SRE sum is not counted twice.
Idempotent: does nothing if the sub-rows already exist. Usage: atomizar-tabla.py <tabla-roadmap.md>
"""
import sys

p = sys.argv[1]
J = "https://smartit-ar.atlassian.net/browse/"


def t(*ids):
    return ", ".join(f"[{i}]({J}{i})" for i in ids)


NO = "No hay ticket aún"
SRE, PLA, CON, PC = "INFRA SRE", "Platform", "Concentrador", "Platform + Concentrador"
DEP = "Depende: si no se modifica código de negocio, se puede hacer sin Dev"

# story -> list of (task, proyecto, ticket, requiere DEV, comentario)
S = {
    2: [
        ("Reunir los datos de accesos no autorizados de los últimos meses", SRE, NO, "No", "Primero se reúnen los datos de los últimos meses"),
        ("Definir las reglas", SRE, NO, "No", ""),
        ("Habilitar las reglas, por etapas (propuesta)", SRE, NO, "No", ""),
        ("Verificar que el tráfico legítimo no se vea afectado", SRE, NO, "Parcial: validación con Dev", "Reto: que todo siga funcionando como hoy"),
    ],
    3: [
        ("Migrar las credenciales de los archivos de entorno a un servicio de AWS", PC, t("GITIN-2129", "GITIN-1606"), "Sí (el código debe leerlas del nuevo servicio)", ""),
        ("Rotación inicial de credenciales", SRE, NO, "Parcial: reinicio y pruebas con Dev", ""),
        ("Rotación automática de las claves de sal", PC, NO, "Sí", "La rotación de claves de sal necesita pruebas y monitoreo a fondo"),
        ("Honeypot con credenciales en los archivos", SRE, NO, "Parcial", ""),
        ("Pruebas posteriores a los cambios", PC, NO, "Sí", "Después de cambiar credenciales hacen falta pruebas extensas"),
    ],
    4: [
        ("Analizar el comportamiento actual del escalado", "INFRA SRE (Platform)", t("GITIN-2170") + " (relacionados: " + t("GITIN-2110", "GITIN-2162") + ")", "No", ""),
        ("Diseñar los umbrales", "INFRA SRE (Platform)", NO, "No", ""),
        ("Implementar los umbrales", "INFRA SRE (Platform)", NO, "No", ""),
        ("Probar y monitorear", "INFRA SRE (Platform)", NO, "No", ""),
    ],
    5: [
        ("Registrar FATAL en Concentrador", CON, t("GITIN-1477"), DEP, "Platform ya registra FATAL; Concentrador no"),
        ("Corregir los defectos del código de registro encontrados en " + t("GITIN-2222"), PLA, t("GITIN-2222"), DEP, "En GITIN-2222 se encontraron además defectos en el propio código de registro"),
        ("Revisar los logs creados hasta hoy", PC, NO, "No", ""),
    ],
    6: [
        ("Contrato de logs", SRE, NO, "Parcial: SRE redacta; Dev revisa y aplica", ""),
        ("Contrato de consultas a Mongo", SRE, NO + " (relacionados: " + t("GITIN-2013", "GITIN-2006") + ")", "Parcial: SRE redacta; Dev revisa y aplica", ""),
    ],
    7: [
        ("Alerta de FATAL de Platform", SRE, t("GITIN-2229"), "No", "Está creada; falta confirmar la entrega de un aviso real"),
        ("Revisar Graylog y analizar nuevas alertas", SRE, NO, "No", ""),
        ("Alerta de FATAL de Concentrador, cuando registre FATAL", SRE, NO, "No (depende de que Concentrador registre FATAL)", "Depende de la fila 5.a"),
        ("Agregar Lambdas al esquema de monitoreo", SRE, t("GITIN-2171"), "No", ""),
    ],
    8: [
        ("Definir el alcance y habilitar Graylog en DEV", SRE, NO, "Parcial: SRE habilita; Dev configura sus ambientes", "El alcance todavía no está definido"),
    ],
    9: [
        ("Separar las responsabilidades del controlador", CON, NO, "Sí", ""),
        ("Eliminar el código de prueba que quedó en producción", CON, NO, "Sí", "Sigue en la rama principal (verificado el 2026-10-15)"),
        ("Unificar las funciones de cierre de sucursal copiadas por plataforma (y las variantes por plataforma de la clase de estado)", CON, NO, "Sí", "Siguen las funciones de cierre copiadas para cinco plataformas; las de chequeo y envío de estado ya se movieron a otra clase, aunque siguen siendo una variante por plataforma"),
        ("Sacar el registro de errores en línea (88 puntos de llamada; depende de la separación)", CON, NO, "Sí", "Depende de la fila 9.a"),
    ],
    10: [
        ("Registrar el error con el pedido y contarlo", CON, NO, DEP, "Confirmado en el código, no en producción"),
        ("Crear una alerta", SRE, NO, "No", ""),
    ],
    11: [
        ("Usar un interceptor HTTP para medir tiempos en lugar de repetir el código en cada plataforma", PLA, NO, DEP, "Verificado en la rama principal el 2026-10-15"),
        ("Pasar los mensajes de error a campos estructurados", PLA, NO, DEP, "Verificado en la rama principal el 2026-10-15"),
    ],
    12: [
        ("Mantener el registro al día y asignar identificadores de Jira", PC, NO, "No", ""),
        ("Registrar lo nuevo de " + t("GITIN-2222") + " (llamadas incorrectas al sanitizador de headers, serialización de errores, política de los manejadores de proceso en Platform y Concentrador)", PC, t("GITIN-2222"), "No", ""),
    ],
}

lines = open(p, encoding="utf-8").read().split("\n")
if any(l.startswith("| 2.a |") for l in lines):
    sys.exit("sub-rows already present, nothing done")
out = []
for l in lines:
    done = False
    for n, tasks in S.items():
        if l.startswith(f"| {n} | "):
            c = [x.strip() for x in l.strip().strip("|").split(" | ")]
            assert len(c) == 9, (n, len(c))
            k = len(tasks)
            L = lambda i: chr(96 + i)
            rng = f"fila {n}.a" if k == 1 else f"filas {n}.a a {n}.{L(k)}"
            c[1] += f" ({rng})"
            c[6] = c[6].rstrip(".") + (f". La {rng} es la tarea de esta historia" if k == 1 else f". Las {rng} son partes de esta historia") + "; la prioridad y la estimación están en esta fila"
            out.append("| " + " | ".join(c) + " |")
            prio = c[7]
            for i, (task, proy, tk, dev, com) in enumerate(tasks, 1):
                note = (com + ". " if com else "") + f"Parte de la historia {n}: prioridad y estimación, las de la fila {n}"
                out.append(f"| {n}.{L(i)} | {task} | Ver fila {n} | {proy} | {tk} | {dev} | {note} | {prio} | Incluida en la fila {n} |")
            done = True
            break
    if not done:
        out.append(l)
open(p, "w", encoding="utf-8").write("\n".join(out))
print("sub-rows added:", sum(len(v) for v in S.values()))
