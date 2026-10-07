"""
Local test harness for handler.py's transform() logic - no AWS calls, no S3.
Runs against the already-downloaded real -3 files in
20260831_lambda-s3-export-utc3/data/consistency_check/.
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from handler import transform, CHAIN_FILTER  # noqa: E402

DATA_DIR = Path(__file__).parent.parent / "20260831_lambda-s3-export-utc3" / "data" / "consistency_check"
FILES = ["news20260828-3.json", "news20260829-3.json", "news20260830-3.json", "news20260831-3.json"]

EXPECTED_TOP_KEYS = {"order", "branchId", "createdAt", "typeId", "updatedAt", "viewed"}
EXPECTED_ORDER_KEYS = {
    "id", "originalId", "displayId", "platformId", "statusId", "orderTime", "deliveryTime",
    "pickupOnShop", "customer", "details", "totalAmount",
}
# Dropped 2026-09-02, narrowed Grido field request: pickupDateOnShop, preOrder,
# observations, ownDelivery. Checked as absent below, not just omitted from the
# expected set, to catch a regression that reintroduces them.
REMOVED_ORDER_KEYS = {"pickupDateOnShop", "preOrder", "observations", "ownDelivery"}
EXPECTED_CUSTOMER_KEYS = {"id", "dni"}
EXPECTED_DETAIL_KEYS = {"productId", "count", "price", "promo", "groupId", "discount", "description", "sku", "canje"}


def main():
    total_all = 0
    total_grido = 0
    schema_errors = []
    sample = None

    for fname in FILES:
        path = DATA_DIR / fname
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                total_all += 1
                record = json.loads(line)
                if record.get("extradata", {}).get("chain") != CHAIN_FILTER:
                    continue
                total_grido += 1
                out = transform(record)

                if set(out.keys()) != EXPECTED_TOP_KEYS:
                    schema_errors.append(f"{fname}: top-level keys mismatch: {set(out.keys())}")
                if set(out["order"].keys()) != EXPECTED_ORDER_KEYS:
                    schema_errors.append(f"{fname}: order keys mismatch: {set(out['order'].keys())}")
                if set(out["order"]["customer"].keys()) != EXPECTED_CUSTOMER_KEYS:
                    schema_errors.append(f"{fname}: customer keys mismatch: {set(out['order']['customer'].keys())}")
                for d in out["order"]["details"]:
                    if set(d.keys()) != EXPECTED_DETAIL_KEYS:
                        schema_errors.append(f"{fname}: detail keys mismatch: {set(d.keys())}")
                        break

                # removed fields must not reappear
                leaked_removed = REMOVED_ORDER_KEYS & set(out["order"].keys())
                if leaked_removed:
                    schema_errors.append(f"{fname}: removed field(s) present: {leaked_removed}")

                # no REDACT fields leaking through
                for banned in ("name", "address", "phone", "email", "tipoIdentificacion"):
                    if banned in out["order"]["customer"]:
                        schema_errors.append(f"{fname}: REDACT field '{banned}' present in customer output")
                if "driver" in out["order"]:
                    schema_errors.append(f"{fname}: REDACT field 'driver' present in order output")

                if sample is None and out["order"]["customer"].get("dni"):
                    sample = out

    print(f"Total records scanned: {total_all}")
    print(f"Grido-chain records:   {total_grido}")
    print(f"Schema errors:         {len(schema_errors)}")
    if schema_errors:
        print("First 10 errors:")
        for e in schema_errors[:10]:
            print(" -", e)
    print()
    print("Sample transformed record (with non-null dni):")
    print(json.dumps(sample, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
