#!/usr/bin/env python3
"""
Generic promotion/discount consistency checker for SmartFran Cloud.

Paste SQL Server query results (SSMS "Copy with headers", tab-separated) for
one or more of the tables below, each under a "## TableName" marker, into a
text file, then run:

    python3 promotion_consistency_check.py --input promos.tsv --country UY

Recognized table names (case-insensitive; alias forms in parentheses are
also accepted): Promotions, PromotionGroups, PromotionDetails, Items, Groups,
PriceDetails. Any subset can be pasted — each check only runs if the tables
it needs are present.

Rules encoded here come from cloud/events/20260802_promocion-invalida-weiss-franui
(see _investigation.md) and are documented in the cloud-invalid-sale skill:

1. Discount-item pricing vs. the minimum-invoicing-amount rule
   (`Groups.FinancialModify == Discount`, priced via `PriceDetails`): a
   percent-based discount item priced at exactly 100 zeroes the sale, which
   is forbidden per-country (AR/UY $0.01, PE $0.30 floor). Priced at
   99.9-99.99 "works" only by accident of subtotal size, since the residual
   is `subtotal * (100 - price) / 100` — proportional to the bill, not a
   fixed floor. Both are flagged.
2. The same structural risk, for the separate `PromotionGroups.Type =
   'PercentDiscount'` mechanism (Business DB combos/promos, not Catalog
   discount items).
3. Promotion date-window coverage gaps: two promotions covering the same
   article where one has expired and the other was never activated.
4. `PromotionGroups` marked as accepting additional/multiple selections but
   with no `PromotionDetails` rows (empty eligible-article list).

Run with --demo to see the checks fire against a built-in dataset shaped
like the WEISS case, with no input file needed.
"""

import argparse
import csv
import io
import sys
from collections import namedtuple, defaultdict
from datetime import date, datetime
from decimal import Decimal, InvalidOperation

MIN_INVOICE_FLOOR = {
    "AR": Decimal("0.01"),
    "UY": Decimal("0.01"),
    "PE": Decimal("0.30"),
}

TABLE_ALIASES = {
    "promotions": "promotions",
    "promotiongroups": "promotiongroups",
    "promotion_groups": "promotiongroups",
    "promotiondetails": "promotiondetails",
    "promotion_details": "promotiondetails",
    "items": "items",
    "groups": "groups",
    "pricedetails": "pricedetails",
    "price_details": "pricedetails",
}

Finding = namedtuple("Finding", ["severity", "rule", "table", "key", "message"])


def normalize_table_name(raw):
    key = "".join(ch for ch in raw.lower() if ch.isalnum())
    return TABLE_ALIASES.get(key, key)


def parse_blocks(text):
    tables = {}
    current_name = None
    current_lines = []

    def flush():
        if current_name and current_lines:
            reader = csv.DictReader(io.StringIO("\n".join(current_lines)), delimiter="\t")
            rows = [row for row in reader if any((v or "").strip() for v in row.values())]
            tables[current_name] = rows

    for line in text.splitlines():
        if line.strip().startswith("##"):
            flush()
            current_name = normalize_table_name(line.strip().lstrip("#").strip())
            current_lines = []
        elif current_name:
            current_lines.append(line)
    flush()
    return tables


def to_decimal(raw):
    if raw is None:
        return None
    raw = raw.strip()
    if raw == "":
        return None
    try:
        return Decimal(raw)
    except InvalidOperation:
        return None


def to_date(raw):
    if raw is None:
        return None
    raw = raw.strip()
    if raw == "":
        return None
    for fmt in ("%Y-%m-%d", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%m/%d/%Y"):
        try:
            return datetime.strptime(raw[: len(fmt) + 2], fmt).date()
        except ValueError:
            continue
    return None


def is_truthy(raw):
    return str(raw or "").strip().lower() in ("1", "true", "yes")


def check_discount_item_pricing(tables, country, today):
    findings = []
    groups = tables.get("groups", [])
    items = tables.get("items", [])
    price_details = tables.get("pricedetails", [])
    if not (groups and items and price_details):
        return findings

    discount_group_ids = {
        row["Id"] for row in groups if str(row.get("FinancialModify", "")).strip() in ("1", "Discount")
    }
    discount_items = {row["Id"]: row.get("Name", "") for row in items if row.get("GroupId") in discount_group_ids}

    floor = MIN_INVOICE_FLOOR.get(country) if country else None
    floor_note = f" (country floor: {country} ${floor})" if floor else ""

    for row in price_details:
        item_id = row.get("ItemId")
        if item_id not in discount_items:
            continue
        item_name = discount_items[item_id]
        for field in ("PublishedPrice", "NewPrice"):
            price = to_decimal(row.get(field))
            if price is None:
                continue
            key = f"Item {item_id} ({item_name}) / PriceList {row.get('PriceListId')} / {field}"
            if price == Decimal("100"):
                findings.append(Finding(
                    "FAIL", "discount-100-percent", "PriceDetails", key,
                    f"{field}=100.00 zeroes the sale outright — violates the minimum-invoicing-amount "
                    f"rule{floor_note}. See PM-confirmed rule in 20260802_promocion-invalida-weiss-franui.",
                ))
            elif Decimal("99.9") <= price < Decimal("100"):
                findings.append(Finding(
                    "WARN", "discount-percent-structural-risk", "PriceDetails", key,
                    f"{field}={price} is a percent-based discount near 100 — residual is "
                    f"subtotal*(100-price)/100, proportional to the bill, not a fixed per-country "
                    f"floor{floor_note}. Only 'works' by accident of subtotal size; can round to $0.00 "
                    f"on small bills or drift far from the intended floor on large ones.",
                ))
    return findings


def check_percent_discount_groups(tables, country):
    findings = []
    promotion_groups = tables.get("promotiongroups", [])
    if not promotion_groups:
        return findings

    floor = MIN_INVOICE_FLOOR.get(country) if country else None
    floor_note = f" (country floor: {country} ${floor})" if floor else ""

    for row in promotion_groups:
        if str(row.get("Type", "")).strip().lower() != "percentdiscount":
            continue
        amount = to_decimal(row.get("Amount"))
        if amount is None:
            continue
        key = f"PromotionGroup {row.get('Id')} (PromotionId {row.get('PromotionId')})"
        if amount == Decimal("100"):
            findings.append(Finding(
                "FAIL", "discount-100-percent", "PromotionGroups", key,
                f"Amount=100 (PercentDiscount) zeroes the sale outright — violates the "
                f"minimum-invoicing-amount rule{floor_note}.",
            ))
        elif Decimal("99.9") <= amount < Decimal("100"):
            findings.append(Finding(
                "WARN", "discount-percent-structural-risk", "PromotionGroups", key,
                f"Amount={amount} (PercentDiscount) is the same structural risk as a Catalog "
                f"discount item near 100%{floor_note} — proportional residual, not a fixed floor.",
            ))
    return findings


def check_promotion_date_gaps(tables, today):
    findings = []
    promotions = tables.get("promotions", [])
    promotion_groups = tables.get("promotiongroups", [])
    promotion_details = tables.get("promotiondetails", [])
    if not (promotions and promotion_groups and promotion_details):
        return findings

    promotions_by_id = {row["Id"]: row for row in promotions}
    group_to_promotion = {row["Id"]: row.get("PromotionId") for row in promotion_groups}

    article_to_promotions = defaultdict(set)
    for row in promotion_details:
        group_id = row.get("PromotionGroupId")
        promo_id = group_to_promotion.get(group_id)
        article_id = row.get("ArticleId")
        if promo_id and article_id:
            article_to_promotions[article_id].add(promo_id)

    seen_pairs = set()
    for article_id, promo_ids in article_to_promotions.items():
        promos = [promotions_by_id[pid] for pid in promo_ids if pid in promotions_by_id]
        if len(promos) < 2:
            continue

        enriched = []
        for p in promos:
            enriched.append({
                "id": p["Id"],
                "name": p.get("Name", ""),
                "activated": to_date(p.get("ActivatedDate")),
                "deactivated": to_date(p.get("DeactivatedDate")),
                "valid_since": to_date(p.get("ValidSinceDate")),
                "valid_to": to_date(p.get("ValidToDate")),
            })

        for expired in enriched:
            if expired["valid_to"] is None or expired["valid_to"] >= today:
                continue
            if expired["activated"] is None:
                continue
            for successor in enriched:
                if successor["id"] == expired["id"]:
                    continue
                if successor["activated"] is not None:
                    continue
                if successor["valid_to"] is None or successor["valid_to"] < today:
                    continue
                pair_key = (article_id, expired["id"], successor["id"])
                if pair_key in seen_pairs:
                    continue
                seen_pairs.add(pair_key)
                findings.append(Finding(
                    "WARN", "promotion-coverage-gap", "Promotions",
                    f"Article {article_id}: {expired['id']} ({expired['name']}) -> {successor['id']} ({successor['name']})",
                    f"Promotion {expired['id']} expired {expired['valid_to']} (ActivatedDate was set); "
                    f"successor {successor['id']} covers the same article through {successor['valid_to']} "
                    f"but ActivatedDate is NULL — never activated. Coverage gap for article {article_id}.",
                ))

        for a in enriched:
            if a["activated"] is None or a["deactivated"] is not None:
                continue
            if not (a["valid_since"] and a["valid_to"] and a["valid_since"] <= today <= a["valid_to"]):
                continue
            for b in enriched:
                if b["id"] <= a["id"]:
                    continue
                if b["activated"] is None or b["deactivated"] is not None:
                    continue
                if not (b["valid_since"] and b["valid_to"] and b["valid_since"] <= today <= b["valid_to"]):
                    continue
                pair_key = (article_id, a["id"], b["id"], "overlap")
                if pair_key in seen_pairs:
                    continue
                seen_pairs.add(pair_key)
                findings.append(Finding(
                    "WARN", "promotion-coverage-overlap", "Promotions",
                    f"Article {article_id}: {a['id']} ({a['name']}) & {b['id']} ({b['name']})",
                    f"Both promotions are currently active and cover the same article {article_id} "
                    f"simultaneously — confirm this overlap is intentional.",
                ))
    return findings


def check_empty_promotion_groups(tables):
    findings = []
    promotion_groups = tables.get("promotiongroups", [])
    promotion_details = tables.get("promotiondetails", [])
    if not promotion_groups:
        return findings

    groups_with_details = {row.get("PromotionGroupId") for row in promotion_details}

    for row in promotion_groups:
        if not (is_truthy(row.get("HasAdditionals")) or is_truthy(row.get("MultipleSelection"))):
            continue
        if row["Id"] in groups_with_details:
            continue
        findings.append(Finding(
            "WARN", "empty-eligible-articles", "PromotionGroups",
            f"PromotionGroup {row['Id']} (PromotionId {row.get('PromotionId')})",
            "HasAdditionals/MultipleSelection is set but no PromotionDetails rows exist for this "
            "group — the eligible-article list is empty.",
        ))
    return findings


CHECKS = [
    lambda tables, country, today: check_discount_item_pricing(tables, country, today),
    lambda tables, country, today: check_percent_discount_groups(tables, country),
    lambda tables, country, today: check_promotion_date_gaps(tables, today),
    lambda tables, country, today: check_empty_promotion_groups(tables),
]

SEVERITY_ORDER = {"FAIL": 0, "WARN": 1, "INFO": 2}


def run_checks(tables, country, today):
    findings = []
    for check in CHECKS:
        findings.extend(check(tables, country, today))
    findings.sort(key=lambda f: (SEVERITY_ORDER.get(f.severity, 9), f.rule, f.table))
    return findings


def print_report(findings, tables):
    present = ", ".join(sorted(tables.keys())) or "(none)"
    print(f"Tables parsed: {present}")
    print(f"Findings: {len(findings)}\n")
    for f in findings:
        print(f"[{f.severity}] {f.rule} — {f.table}: {f.key}")
        print(f"    {f.message}\n")
    if not findings:
        print("No consistency issues detected against the encoded rules.")


DEMO_INPUT = """## Groups
Id\tName\tFinancialModify
243\tDescuento\t1

## Items
Id\tName\tGroupId
430\tDescuento Influencers 100%\t243

## PriceDetails
ItemId\tPriceListId\tPublishedPrice\tNewPrice\tEnabled
430\t910\t99.99\t99.99\tTrue
430\t908\t100.00\t100.00\tTrue

## Promotions
Id\tName\tPromotionType\tValidSinceDate\tValidToDate\tActivatedDate\tDeactivatedDate
183\tRuleta Articulo Bonificado\t0\t2026-01-01\t2026-07-31\t2026-01-01\t
186\tRuleta Articulo Bonificado v2\t0\t2026-08-01\t2028-03-31\t\t

## PromotionGroups
Id\tPromotionId\tType\tAmount\tHasAdditionals\tMultipleSelection
900\t183\tPercentDiscount\t100\tTrue\tFalse
901\t186\tPercentDiscount\t50\tTrue\tFalse
902\t186\tFixedDiscount\t20\tTrue\tFalse

## PromotionDetails
PromotionGroupId\tArticleId
900\t386
901\t386
"""


def main():
    parser = argparse.ArgumentParser(description="Generic SmartFran Cloud promotion consistency checker")
    parser.add_argument("--input", help="Path to a text file with pasted TSV table blocks. Omit to read stdin.")
    parser.add_argument("--country", choices=sorted(MIN_INVOICE_FLOOR), help="Tenant country, for floor context in messages.")
    parser.add_argument("--today", help="Override today's date (YYYY-MM-DD), default: real today.")
    parser.add_argument("--demo", action="store_true", help="Run against a built-in WEISS-shaped dataset, ignore --input.")
    args = parser.parse_args()

    today = to_date(args.today) if args.today else date.today()

    if args.demo:
        text = DEMO_INPUT
    elif args.input:
        with open(args.input, "r", encoding="utf-8") as fh:
            text = fh.read()
    else:
        text = sys.stdin.read()

    tables = parse_blocks(text)
    findings = run_checks(tables, args.country, today)
    print_report(findings, tables)

    if any(f.severity == "FAIL" for f in findings):
        sys.exit(1)


if __name__ == "__main__":
    main()
