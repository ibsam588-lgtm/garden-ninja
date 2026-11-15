"""Small App Store Connect client. Credentials stay in the process environment."""

import base64
import json
import os
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.corsairlabs.gardenNinja"


class AppleError(RuntimeError):
    def __init__(self, status, detail):
        self.status = status
        super().__init__(f"Apple HTTP {status}: {detail}")


class AppleAPI:
    def __init__(self, env=None):
        self.env = os.environ if env is None else env
        self.key = serialization.load_pem_private_key(
            self.env["APP_STORE_CONNECT_PRIVATE_KEY"].encode(), password=None
        )

    def token(self):
        def encode(value):
            return base64.urlsafe_b64encode(value).rstrip(b"=").decode()

        now = int(time.time())
        header = encode(json.dumps({"alg": "ES256", "kid": self.env["APP_STORE_CONNECT_KEY_IDENTIFIER"], "typ": "JWT"}).encode())
        claims = encode(json.dumps({"iss": self.env["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 300, "aud": "appstoreconnect-v1"}).encode())
        unsigned = f"{header}.{claims}"
        r, s = decode_dss_signature(self.key.sign(unsigned.encode(), ec.ECDSA(hashes.SHA256())))
        return f"{unsigned}.{encode(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"

    def request(self, method, path, payload=None):
        if not path.startswith("/v1/") and not path.startswith("/v2/"):
            raise ValueError("Only App Store Connect resource paths are allowed")
        for attempt in range(4):
            req = Request(BASE + path, method=method,
                          data=None if payload is None else json.dumps(payload).encode(),
                          headers={"Authorization": "Bearer " + self.token(), "Content-Type": "application/json"})
            try:
                with urlopen(req, timeout=60) as response:
                    raw = response.read()
                    return json.loads(raw) if raw else {}
            except HTTPError as error:
                if method == "GET" and (error.code == 429 or error.code >= 500) and attempt < 3:
                    time.sleep(2 ** attempt)
                    continue
                body = json.loads(error.read())
                detail = "; ".join(e.get("detail", e.get("title", "")) for e in body.get("errors", []))
                raise AppleError(error.code, detail[:1500]) from None
            except URLError:
                if method != "GET" or attempt == 3:
                    raise RuntimeError("App Store Connect could not be reached") from None
                time.sleep(2 ** attempt)

    def all(self, path):
        resources = []
        while path:
            response = self.request("GET", path)
            resources.extend(response["data"])
            link = response.get("links", {}).get("next")
            if link:
                url = urlparse(link)
                if f"{url.scheme}://{url.netloc}" != BASE:
                    raise ValueError("Unexpected App Store Connect pagination host")
                path = url.path + ("?" + url.query if url.query else "")
            else:
                path = None
        return resources


def relation(kind, identifier):
    return {"data": {"type": kind, "id": identifier}}
