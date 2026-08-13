#!/usr/bin/env python3
"""
Mockup validation for 20260802_promocion-invalida-weiss-franui.

Replicates, with real numbers pulled from SmartFran.Cloud.Catalog_WEISS /
Business_WEISS, the exact formulas read from the POS source
(cloud/repo/SmartFran.Cloud/Source/Pos/.../Sale.razor.cs) and the backend
validator (SmartFran.Cloud.Sales.Application/.../SaleCreateCmdValidator.cs),
to confirm the root cause deterministically instead of by approximation.

Formula 1 — CalcAmountWithOutIva (Sale.razor.cs:1317-1332):
    itemFinancial.Total = totalWithOutTax * (discountItem.Price / 100) * -1

Formula 2 — SaleCreateCmdValidator / ValidateAmount (both identical):
    total = sum(Quantity * UnitPrice) over non-body lines
    valid = payments >= total
"""

from decimal import Decimal, ROUND_HALF_UP


def apply_discount(subtotal: Decimal, discount_price: Decimal) -> Decimal:
    """Mirrors CalcAmountWithOutIva: discount_price is used directly as a percentage."""
    discount_total = (subtotal * (discount_price / Decimal(100)) * Decimal(-1))
    return subtotal + discount_total  # amount actually owed after discount


def validate_amount(total_owed: Decimal, payments: Decimal) -> bool:
    """Mirrors SaleCreateCmdValidator's Must() rule: payments >= total."""
    return payments >= total_owed


def scenario(name: str, subtotal: Decimal, discount_price: Decimal, payments: Decimal):
    owed = apply_discount(subtotal, discount_price).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    residual = (subtotal - (subtotal - owed)).quantize(Decimal("0.01"))  # == owed, kept explicit for clarity
    ok = validate_amount(owed, payments)
    print(f"{name}")
    print(f"  subtotal={subtotal}  discount_price={discount_price}%  owed_after_discount={owed}  payments={payments}")
    print(f"  SaleCreateCmdValidator result: {'ACCEPTED' if ok else 'REJECTED (SaleIsInvalid, 12000)'}")
    print()


if __name__ == "__main__":
    DISCOUNT_BUGGED = Decimal("99.99")   # real value found in PriceDetails for Item 430, all 8 rows
    DISCOUNT_FIXED = Decimal("100.00")   # proposed corrected value

    print("=== Reproducing the two reported real cases with the BUGGED discount value ===\n")

    # Case A: 2 hamburguesas alone, discount applied, customer pays $0 expecting a free sale
    scenario(
        "Case A — 2 hamburguesas combo alone (reported PASS, total shown $0.14)",
        subtotal=Decimal("1400.00"), discount_price=DISCOUNT_BUGGED, payments=Decimal("0.00"),
    )

    # Case B: 2 hamburguesas + Franui (plain), discount applied, customer pays $0
    scenario(
        "Case B — 2 hamburguesas + Franui simple (reported FAIL, total shown $0.17)",
        subtotal=Decimal("1700.00"), discount_price=DISCOUNT_BUGGED, payments=Decimal("0.00"),
    )

    print("=== Same two cases with the FIX applied (discount price = 100.00) ===\n")

    scenario(
        "Case A (fixed)", subtotal=Decimal("1400.00"), discount_price=DISCOUNT_FIXED, payments=Decimal("0.00"),
    )
    scenario(
        "Case B (fixed)", subtotal=Decimal("1700.00"), discount_price=DISCOUNT_FIXED, payments=Decimal("0.00"),
    )

    print("=== Sensitivity: residual is EXACTLY subtotal * 0.0001 for any clean whole-dollar subtotal ===\n")
    for sub in (Decimal("1400.00"), Decimal("1700.00"), Decimal("250.00"), Decimal("7900.00"), Decimal("8900.00")):
        owed = apply_discount(sub, DISCOUNT_BUGGED).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        print(f"  subtotal={sub:>10}  -> residual owed = {owed}  (= subtotal * 0.0001)")
