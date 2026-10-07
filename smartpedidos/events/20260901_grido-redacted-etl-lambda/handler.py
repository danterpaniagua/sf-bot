"""
GITIN-1874 (presumed, not yet confirmed) - Grido redacted ETL.

Reads the already-exported `-3` files from smartfranbkp/news/ (GITIN-1970/1980's
output), filters to Grido-chain records (extradata.chain == "Grido" - confirmed
platform-agnostic filter, see investigation.md), applies the field allow-list
confirmed directly against Grido's own requested shape, and writes the result to
smartpedidos-orders/grido/.

Field allow-list, casing, and the observations/dni decisions are all documented in
investigation.md - this file implements those decisions, it does not re-derive them.

Core config (all optional, all have Lambda-safe defaults matching Grido's current setup):
  SOURCE_BUCKET=name           default: smartfranbkp
  DEST_BUCKET=name             default: smartpedidos-orders
  DEST_PREFIX=name             default: grido - the platform prefix under DEST_BUCKET
  CHAIN_FILTER=name            default: Grido - extradata.chain value to filter on
  DAYSBEFORE=N                 default: 2 - rolling window for a real scheduled trigger
  REGION=name                  default: us-east-1

Local/historical-run only (no Lambda-safe default needed, all optional):
  DRY_RUN=true                 don't write to DEST_BUCKET, just report counts
  START_DATE=YYYY-MM-DD        explicit range start - overrides DAYSBEFORE when set with END_DATE
  END_DATE=YYYY-MM-DD          explicit range end
  RESUME=true                  skip days already recorded in PROGRESS_FILE
  PROGRESS_FILE=path           default: progress.txt next to this script
  PROFILE=name                 ~/.aws/credentials profile to use (default: active/env vars)

To serve a different platform, redeploy this same code as a separate Lambda with
different DEST_PREFIX/CHAIN_FILTER/DEST_BUCKET env vars - the field allow-list and
transform() itself are not platform-specific in principle, but haven't been
validated against any platform other than Grido's confirmed field request.
"""

import json
import os
from datetime import datetime, timedelta, timezone

import boto3
from botocore.exceptions import ClientError

SOURCE_BUCKET = os.environ.get("SOURCE_BUCKET", "smartfranbkp")
SOURCE_PREFIX = "news"  # fixed - always reads from the news/ export, not platform-specific
DEST_BUCKET = os.environ.get("DEST_BUCKET", "smartpedidos-orders")
DEST_PREFIX = os.environ.get("DEST_PREFIX", "grido")
DAYS_BEFORE = int(os.environ.get("DAYSBEFORE", "2"))
CHAIN_FILTER = os.environ.get("CHAIN_FILTER", "Grido")
REGION = os.environ.get("REGION", "us-east-1")
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"

# Explicit range for historical/local runs - if both set, overrides the rolling
# DAYSBEFORE window (which stays the default for a real scheduled Lambda trigger).
START_DATE = os.environ.get("START_DATE")  # YYYY-MM-DD
END_DATE = os.environ.get("END_DATE")  # YYYY-MM-DD

RESUME = os.environ.get("RESUME", "false").lower() == "true"
PROGRESS_FILE = os.environ.get(
    "PROGRESS_FILE",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "progress.txt"),
)

PROFILE = os.environ.get("PROFILE")  # ~/.aws/credentials profile name, for local runs
_session = boto3.Session(profile_name=PROFILE) if PROFILE else boto3.Session()
s3 = _session.client("s3", region_name=REGION)


def load_progress():
    if not os.path.exists(PROGRESS_FILE):
        return set()
    with open(PROGRESS_FILE) as f:
        return {line.strip() for line in f if line.strip()}


def mark_done(label):
    with open(PROGRESS_FILE, "a") as f:
        f.write(label + "\n")
        f.flush()


def source_key(day):
    return f"{SOURCE_PREFIX}/{day.strftime('%Y')}/{day.strftime('%m')}/news{day.strftime('%Y%m%d')}-3.json"


def dest_key(day):
    return f"{DEST_PREFIX}/{day.strftime('%Y')}/{day.strftime('%m')}/news{day.strftime('%Y%m%d')}.json"


def as_date(value):
    """Wrap an ISO timestamp string as MongoDB Extended JSON, matching Grido's spec."""
    if not value:
        return None
    return {"$date": value}


def get_ci(d, *keys):
    """Return the first present key's value, trying multiple casings/names in order.

    Real bug found 2026-09-02 (see investigation.md, H8): source `-3` files before
    ~2026-08-17 are in the raw MongoDB document shape (extraData, originalId,
    platformId, createdAt, updatedAt - orderMapper()'s input), while files from
    ~2026-08-17 onward are orderMapper()'s transformed shape (extradata, originalid,
    platformid, createdat, updatedat). Every field whose name differs between the two
    shapes goes through this instead of a bare .get() - a plain .get() silently
    returned None on the older shape for every such field, not just chain, making
    transform() treat 46,917+ real Grido records/day as no-grido-records.
    """
    for k in keys:
        if k in d:
            return d[k]
    return None


def get_extradata(record):
    return get_ci(record, "extradata", "extraData") or {}


def transform(record):
    order = record.get("order", {})
    customer = order.get("customer", {})
    order_id = order.get("id")

    details = []
    for d in order.get("details", []):
        product_id = get_ci(d, "productid", "productId")
        group_id = get_ci(d, "groupid", "groupId")
        details.append({
            "productId": str(product_id) if product_id is not None else None,
            "count": str(d.get("count")) if d.get("count") is not None else None,
            "price": str(d.get("price")) if d.get("price") is not None else None,
            "promo": d.get("promo"),
            "groupId": int(group_id) if str(group_id if group_id is not None else "").lstrip("-").isdigit() else group_id,
            "discount": str(d.get("discount")) if d.get("discount") not in (None,) else "",
            "description": d.get("description"),
            "sku": str(d.get("sku")) if d.get("sku") is not None else None,
            "canje": d.get("canje", 0),
        })

    return {
        "order": {
            "id": str(order_id) if order_id is not None else None,
            "originalId": str(order_id) if order_id is not None else None,
            "displayId": str(order_id) if order_id is not None else None,
            "platformId": get_ci(order, "platformid", "platformId"),
            "statusId": get_ci(order, "statusid", "statusId"),
            "orderTime": as_date(get_ci(order, "ordertime", "orderTime")),
            "deliveryTime": as_date(get_ci(order, "deliverytime", "deliveryTime")),
            "pickupOnShop": get_ci(order, "pickuponshop", "pickupOnShop"),
            # pickupDateOnShop, preOrder, observations, ownDelivery dropped from the allow-list
            # 2026-09-02 - Grido's field request narrowed, see investigation.md.
            "customer": {
                "id": str(customer.get("id")) if customer.get("id") is not None else None,
                "dni": customer.get("dni"),  # included per confirmed business decision - see investigation.md
            },
            "details": details,
            "totalAmount": get_ci(order, "totalamount", "totalAmount"),
        },
        "branchId": record.get("branchId"),
        "createdAt": as_date(get_ci(record, "createdat", "createdAt")),
        "typeId": record.get("typeId"),
        "updatedAt": as_date(get_ci(record, "updatedat", "updatedAt")),
        "viewed": as_date(record.get("viewed")),
    }


def process_day(day, resume_done=None):
    label = day.strftime("%Y%m%d")

    if resume_done and label in resume_done:
        print(f"[{label}] ya completado segun {PROGRESS_FILE} - se omite (RESUME)")
        return {"day": label, "status": "skipped-resume"}

    src_key = source_key(day)
    try:
        res = s3.get_object(Bucket=SOURCE_BUCKET, Key=src_key)
    except ClientError as err:
        if err.response["Error"]["Code"] == "NoSuchKey":
            print(f"[{label}] no existe {src_key} - se omite")
            return {"day": label, "status": "missing-source"}
        raise

    text = res["Body"].read().decode("utf-8")
    matched = []
    total = 0
    for line in text.split("\n"):
        line = line.strip()
        if not line:
            continue
        total += 1
        record = json.loads(line)
        if get_extradata(record).get("chain") != CHAIN_FILTER:
            continue
        matched.append(json.dumps(transform(record), ensure_ascii=False))

    print(f"[{label}] {len(matched)}/{total} registros Grido")

    if not matched:
        return {"day": label, "status": "no-grido-records", "total": total}

    out_key = dest_key(day)

    if DRY_RUN:
        print(f"[{label}] --dry-run: no se escribe {DEST_BUCKET}/{out_key} ({len(matched)} registros)")
        return {"day": label, "status": "dry-run", "count": len(matched)}

    body = "\n".join(matched) + "\n"
    s3.put_object(Bucket=DEST_BUCKET, Key=out_key, Body=body.encode("utf-8"))
    if RESUME:
        mark_done(label)
    print(f"[{label}] escrito {out_key}")
    return {"day": label, "status": "written", "count": len(matched)}


def handle(event=None, context=None):
    resume_done = load_progress() if RESUME else set()
    if RESUME and resume_done:
        print(f"RESUME: {len(resume_done)} dia(s) ya completados segun {PROGRESS_FILE}, se omiten")

    results = []

    if START_DATE and END_DATE:
        cursor = datetime.strptime(START_DATE, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        end = datetime.strptime(END_DATE, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        print(f"Rango explicito: {START_DATE} a {END_DATE} ({'DRY RUN' if DRY_RUN else 'ESCRITURA REAL'})")
        while cursor <= end:
            results.append(process_day(cursor, resume_done))
            cursor += timedelta(days=1)
    else:
        today = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
        for offset in range(1, DAYS_BEFORE + 1):
            day = today - timedelta(days=offset)
            results.append(process_day(day, resume_done))

    print("--- Resumen ---")
    summary = {}
    for r in results:
        summary[r["status"]] = summary.get(r["status"], 0) + 1
    print(summary)
    return results


if __name__ == "__main__":
    handle()
