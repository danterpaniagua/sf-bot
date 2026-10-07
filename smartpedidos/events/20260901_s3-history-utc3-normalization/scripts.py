#!/usr/bin/env python3
"""
GITIN-1980 - Normaliza el historial de S3 (news/) a limites de dia Argentina (UTC-3).

Para cada dia D (calendario Argentina) en el rango, lee los archivos S3 de los dias
UTC D y D+1, filtra los registros cuyo updatedAt cae dentro del dia Argentina D, y
escribe ese subconjunto SIN MODIFICAR (mismas lineas de texto originales, sin
re-serializar) a newsYYYYMMDD-3.json en la misma carpeta.

Rango por defecto confirmado en investigation.md (limite hot/cold S3 + disponibilidad
de D+1): 2025-08-17 a 2026-08-30.

Uso:
    python scripts.py --dry-run                              # probar sin escribir a S3
    python scripts.py --start 2025-08-17 --end 2025-08-20     # rango acotado, prueba real
    python scripts.py                                          # rango completo por defecto
    python scripts.py --resume                                 # reintentar tras una falla,
                                                                 # sin reprocesar dias ya escritos

Flags:
    --start YYYY-MM-DD   (default 2025-08-17)
    --end YYYY-MM-DD     (default 2026-08-30)
    --dry-run            no escribe a S3, solo reporta cuantos registros por dia
    --skip-existing      si newsYYYYMMDD-3.json ya existe en S3, no lo regenera (chequeo remoto)
    --resume             salta dias ya completados segun el archivo de progreso local
                          (chequeo local, mas rapido que --skip-existing en una corrida larga)
    --progress-file PATH archivo de progreso (default: progress.txt junto al script)
    --profile PERFIL     perfil de ~/.aws/credentials a usar (default: el activo/env vars)
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone

import boto3
from botocore.exceptions import ClientError

BUCKET = "smartfranbkp"
REGION = "us-east-1"
COLLECTION = "news"

DEFAULT_START = "2025-08-17"
DEFAULT_END = "2026-08-30"
DEFAULT_PROGRESS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "progress.txt")

s3 = None  # inicializado en main() una vez parseado --profile


def parse_args():
    parser = argparse.ArgumentParser(description="Normaliza historial S3 news/ a UTC-3")
    parser.add_argument("--start", default=DEFAULT_START)
    parser.add_argument("--end", default=DEFAULT_END)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-existing", action="store_true")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--progress-file", default=DEFAULT_PROGRESS_FILE)
    parser.add_argument("--profile", default=None, help="Perfil de ~/.aws/credentials a usar")
    return parser.parse_args()


def load_progress(progress_file):
    if not os.path.exists(progress_file):
        return set()
    with open(progress_file, "r") as f:
        return {line.strip() for line in f if line.strip()}


def mark_done(progress_file, label):
    with open(progress_file, "a") as f:
        f.write(label + "\n")
        f.flush()


def ymd(date_utc_midnight):
    return (
        date_utc_midnight.strftime("%Y"),
        date_utc_midnight.strftime("%m"),
        date_utc_midnight.strftime("%d"),
    )


def s3_key_for_day(date_utc_midnight, suffix=""):
    year, month, day = ymd(date_utc_midnight)
    return f"{COLLECTION}/{year}/{month}/news{year}{month}{day}{suffix}.json"


def get_object_lines(key):
    try:
        res = s3.get_object(Bucket=BUCKET, Key=key)
        text = res["Body"].read().decode("utf-8")
        return [line for line in text.split("\n") if line.strip()]
    except ClientError as err:
        if err.response["Error"]["Code"] == "NoSuchKey":
            print(f"  ADVERTENCIA: no existe {key} - se omite como fuente para este dia", file=sys.stderr)
            return None
        raise


def argentina_day_bounds_utc(day_utc_midnight):
    # Argentina (UTC-3, sin DST) dia D en terminos UTC: [D 03:00, D+1 03:00)
    lower = day_utc_midnight.replace(hour=3, minute=0, second=0, microsecond=0)
    upper = lower + timedelta(days=1)
    return lower, upper


def parse_record_updated_at(record):
    # Casing depende de si el archivo fuente fue escrito antes o despues del fix de
    # orderMapper (GITIN-1970, H4) - se soportan ambas variantes por robustez.
    raw = record.get("updatedAt") or record.get("updatedat")
    if not raw:
        return None
    normalized = raw.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def process_day(day_utc_midnight, dry_run, skip_existing, resume_done, progress_file):
    year, month, day = ymd(day_utc_midnight)
    label = f"{year}{month}{day}"
    out_key = s3_key_for_day(day_utc_midnight, "-3")

    if label in resume_done:
        print(f"[{label}] ya completado segun {progress_file} - se omite (--resume)")
        return {"label": label, "status": "skipped-resume"}

    if skip_existing:
        try:
            s3.head_object(Bucket=BUCKET, Key=out_key)
            print(f"[{label}] ya existe {out_key} - se omite (--skip-existing)")
            mark_done(progress_file, label)
            return {"label": label, "status": "skipped-existing"}
        except ClientError as err:
            if err.response["Error"]["Code"] != "404":
                raise

    key_d = s3_key_for_day(day_utc_midnight)
    key_d1 = s3_key_for_day(day_utc_midnight + timedelta(days=1))

    print(f"[{label}] leyendo {key_d} + {key_d1}")
    lines_d = get_object_lines(key_d)
    lines_d1 = get_object_lines(key_d1)

    if lines_d is None or lines_d1 is None:
        print(f"[{label}] FALTA archivo fuente - dia omitido, requiere revision manual", file=sys.stderr)
        return {"label": label, "status": "missing-source"}

    lower, upper = argentina_day_bounds_utc(day_utc_midnight)
    matched_lines = []
    skipped_no_timestamp = 0
    from_d, from_d1 = 0, 0

    for source_name, source_lines in (("D", lines_d), ("D+1", lines_d1)):
        for line in source_lines:
            try:
                record = json.loads(line)
            except json.JSONDecodeError as err:
                print(f"[{label}] linea no parseable como JSON, se omite: {err}", file=sys.stderr)
                continue
            updated_at = parse_record_updated_at(record)
            if updated_at is None:
                skipped_no_timestamp += 1
                continue
            if lower <= updated_at < upper:
                matched_lines.append(line)  # linea ORIGINAL sin modificar
                if source_name == "D":
                    from_d += 1
                else:
                    from_d1 += 1

    if skipped_no_timestamp:
        print(f"[{label}] {skipped_no_timestamp} registro(s) sin updatedAt/updatedat - omitidos", file=sys.stderr)

    print(f"[{label}] {len(matched_lines)} registro(s) para {out_key} (desde D: {from_d}, desde D+1: {from_d1})")

    if dry_run:
        print(f"[{label}] --dry-run: no se escribe a S3")
        return {"label": label, "status": "dry-run", "count": len(matched_lines)}

    body = "".join(line + "\n" for line in matched_lines)
    s3.put_object(Bucket=BUCKET, Key=out_key, Body=body.encode("utf-8"))
    mark_done(progress_file, label)
    print(f"[{label}] escrito {out_key}")
    return {"label": label, "status": "written", "count": len(matched_lines)}


def main():
    global s3
    args = parse_args()
    session = boto3.Session(profile_name=args.profile) if args.profile else boto3.Session()
    s3 = session.client("s3", region_name=REGION)

    start_date = datetime.strptime(args.start, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    end_date = datetime.strptime(args.end, "%Y-%m-%d").replace(tzinfo=timezone.utc)

    print(f"Rango: {args.start} a {args.end} ({'DRY RUN' if args.dry_run else 'ESCRITURA REAL'})")

    resume_done = load_progress(args.progress_file) if args.resume else set()
    if args.resume and resume_done:
        print(f"--resume: {len(resume_done)} dia(s) ya completados segun {args.progress_file}, se omiten")

    results = []
    cursor = start_date
    while cursor <= end_date:
        result = process_day(cursor, args.dry_run, args.skip_existing, resume_done, args.progress_file)
        results.append(result)
        cursor += timedelta(days=1)

    summary = {}
    for r in results:
        summary[r["status"]] = summary.get(r["status"], 0) + 1
    print("--- Resumen ---")
    print(summary)

    problems = [r for r in results if r["status"] == "missing-source"]
    if problems:
        print("Dias con archivo fuente faltante (revisar manualmente):")
        for r in problems:
            print(f"  - {r['label']}")


if __name__ == "__main__":
    main()
