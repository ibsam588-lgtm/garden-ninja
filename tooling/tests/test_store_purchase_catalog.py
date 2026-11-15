"""Guard the approved price and prevent catalog automation changing other SKUs."""
import copy
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from configure_google_purchase import product_payload, verify_product


class StoreCatalogTests(unittest.TestCase):
    def setUp(self):
        self.product = product_payload({
            "convertedRegionPrices": {
                "US": {"price": {"currencyCode": "USD", "units": "2", "nanos": 990000000}},
                "DE": {"price": {"currencyCode": "EUR", "units": "2", "nanos": 890000000}},
            },
            "convertedOtherRegionsPrice": {
                "usdPrice": {"currencyCode": "USD", "units": "2", "nanos": 990000000},
                "eurPrice": {"currencyCode": "EUR", "units": "2", "nanos": 890000000},
            },
        })

    def test_local_store_prices_and_permanent_single_purchase(self):
        option = verify_product(self.product)
        self.assertTrue(option["buyOption"]["legacyCompatible"])
        germany = next(r for r in option["regionalPricingAndAvailabilityConfigs"] if r["regionCode"] == "DE")
        self.assertEqual(germany["price"]["currencyCode"], "EUR")
        self.assertEqual(germany["price"]["nanos"], 890000000)

    def test_unapproved_price_or_identity_cannot_be_overwritten(self):
        for field, value in [("packageName", "another.app"), ("productId", "coin_pack")]:
            product = copy.deepcopy(self.product)
            product[field] = value
            with self.assertRaises(ValueError):
                verify_product(product)
        us = next(r for r in self.product["purchaseOptions"][0]["regionalPricingAndAvailabilityConfigs"] if r["regionCode"] == "US")
        us["price"]["units"] = "3"
        with self.assertRaises(ValueError):
            verify_product(self.product)

    def test_rental_multi_quantity_and_extra_options_are_rejected(self):
        for field in ["rental", "multi", "extra"]:
            product = copy.deepcopy(self.product)
            option = product["purchaseOptions"][0]
            if field == "rental":
                option.pop("buyOption")
                option["rentOption"] = {"rentalPeriod": "P1D"}
            elif field == "multi":
                option["buyOption"]["multiQuantityEnabled"] = True
            else:
                product["purchaseOptions"].append(copy.deepcopy(option))
            with self.assertRaises(ValueError):
                verify_product(product)
