"""Provision only the owner's approved Garden Ninja $2.99 Remove Ads product.

Run manually from main in Actions; authentication stays on the runner. A normal
build never changes product prices. No customer purchases are made by this tool.
"""
import argparse
import json
import os
import re
from decimal import Decimal

PACKAGE = "com.gardenninja.garden_ninja"
PRODUCT = "garden_ninja_remove_ads"
OPTION = "buy"
USD_PRICE = {"currencyCode": "USD", "units": "2", "nanos": 990000000}
BASE = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"


def product_payload(conversion):
    regions = [
        {"regionCode": region, "price": value["price"], "availability": "AVAILABLE"}
        for region, value in sorted(conversion["convertedRegionPrices"].items())
    ]
    us = next(r for r in regions if r["regionCode"] == "US")
    us["price"] = USD_PRICE.copy()
    return {
        "packageName": PACKAGE,
        "productId": PRODUCT,
        "listings": [{
            "languageCode": "en-US", "title": "Remove Ads",
            "description": "Permanently remove banners and automatic ad breaks with one purchase. Optional rewarded videos remain available.",
        }],
        "purchaseOptions": [{
            "purchaseOptionId": OPTION,
            "buyOption": {"legacyCompatible": True, "multiQuantityEnabled": False},
            "regionalPricingAndAvailabilityConfigs": regions,
            "newRegionsConfig": {
                **conversion["convertedOtherRegionsPrice"], "availability": "AVAILABLE",
            },
        }],
    }


def verify_product(product):
    if product.get("packageName") != PACKAGE or product.get("productId") != PRODUCT:
        raise ValueError("Unexpected app or product in store response")
    options = product["purchaseOptions"]
    if len(options) != 1 or options[0].get("purchaseOptionId") != OPTION:
        raise ValueError("Unexpected existing purchase options; inspect before updating")
    option = options[0]
    if "buyOption" not in option or option["buyOption"].get("multiQuantityEnabled", False):
        raise ValueError("Remove Ads must be a single permanent purchase")
    if not option["buyOption"].get("legacyCompatible", False):
        raise ValueError("The default buy option must support the app's compatible billing flow")
    us = next(r for r in option["regionalPricingAndAvailabilityConfigs"] if r["regionCode"] == "US")
    if us.get("availability") != "AVAILABLE":
        raise ValueError("The approved US purchase option is not available")
    price = us["price"]
    amount = Decimal(price.get("units", "0")) + Decimal(price.get("nanos", 0)) / 1000000000
    if price["currencyCode"] != "USD" or amount != Decimal("2.99"):
        raise ValueError("Existing US price differs from the approved $2.99; refusing to overwrite")
    return option


def configure(session, apply=False):
    def request(method, path, **kwargs):
        response = session.request(method, BASE + path, timeout=60, **kwargs)
        if response.status_code == 404 and method == "GET":
            return None
        if not response.ok:
            # Report the provider's actionable catalog error, without headers,
            # credentials, or any account email it includes.
            try:
                detail = response.json().get("error", {}).get("message", "")
            except ValueError:
                detail = ""
            detail = re.sub(r"[\w.+%-]+@[\w.-]+\.[A-Za-z]{2,}", "[account]", detail)[:500]
            raise RuntimeError(f"Google Play catalog {method} failed: HTTP {response.status_code}. {detail}")
        return response.json() if response.content else {}

    path = f"/onetimeproducts/{PRODUCT}"
    product = request("GET", path)
    if product:
        option = verify_product(product)
        print(f"Existing approved product: {PRODUCT}; option={option.get('state')}")
    elif not apply:
        print(f"Product missing: {PRODUCT}; planned base price USD 2.99, permanent single buy")
        return
    else:
        conversion = request("POST", "/pricing:convertRegionPrices", json={"price": USD_PRICE})
        product = request("PATCH", path, params={
            "allowMissing": "true", "updateMask": "listings,purchaseOptions",
            "regionsVersion.version": conversion["regionVersion"]["version"],
        }, json=product_payload(conversion))
        option = verify_product(product)
        print(f"Created approved product: {PRODUCT}; USD 2.99; localized store equivalents")
    if apply and option.get("state") != "ACTIVE":
        request("POST", f"/oneTimeProducts/{PRODUCT}/purchaseOptions:batchUpdateStates", json={
            "requests": [{"activatePurchaseOptionRequest": {
                "packageName": PACKAGE, "productId": PRODUCT, "purchaseOptionId": OPTION,
            }}],
        })
        product = request("GET", path)
        option = verify_product(product)
        if option.get("state") != "ACTIVE":
            raise RuntimeError("Purchase option was not confirmed ACTIVE")
    print(f"Verified {PRODUCT}: {option.get('state')}; no customer transaction was performed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2 import service_account
    credentials = service_account.Credentials.from_service_account_info(
        json.loads(os.environ["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"]),
        scopes=["https://www.googleapis.com/auth/androidpublisher"],
    )
    with AuthorizedSession(credentials) as session:
        configure(session, args.apply)


if __name__ == "__main__":
    main()
