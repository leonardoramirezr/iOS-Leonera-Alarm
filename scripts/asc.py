#!/usr/bin/env python3
"""Small App Store Connect API client for CI (Python stdlib + the openssl CLI).

Credentials come from the environment:
    ASC_KEY_ID      key ID
    ASC_ISSUER_ID   issuer ID (Team Key)
    ASC_KEY_PATH    path to the AuthKey_XXXX.p8 file

Commands:
    check [--udids-out FILE]
        Checks that the key works and that at least one iOS device is registered.
        Optionally writes the UDIDs of the enabled iPhones/iPads, one per line.
    dev-serials
        Prints the serial numbers of the "Apple Development" certificates in the
        keychain (macOS), one per line.
    revoke-new-dev-certs --before FILE
        Revokes, through the API, the "Apple Development" certificates that are in
        the keychain now but whose serial is not listed in FILE (the output of
        dev-serials taken before xcodebuild created a new one).
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
DEV_CERT_TYPES = "DEVELOPMENT,IOS_DEVELOPMENT"


def fail(message):
    print("error: " + message, file=sys.stderr)
    sys.exit(1)


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der):
    """ECDSA DER signature (SEQUENCE of two INTEGERs) -> 64-byte r||s for ES256."""

    def read_length(pos):
        length = der[pos]
        pos += 1
        if length & 0x80:
            count = length & 0x7F
            length = int.from_bytes(der[pos:pos + count], "big")
            pos += count
        return length, pos

    if der[0] != 0x30:
        raise ValueError("signature is not a DER sequence")
    _, pos = read_length(1)
    parts = []
    for _ in range(2):
        if der[pos] != 0x02:
            raise ValueError("signature integer expected")
        length, pos = read_length(pos + 1)
        value = der[pos:pos + length].lstrip(b"\x00")
        pos += length
        if len(value) > 32:
            raise ValueError("signature integer too long")
        parts.append(value.rjust(32, b"\x00"))
    return parts[0] + parts[1]


def make_token():
    key_id = os.environ.get("ASC_KEY_ID", "").strip()
    issuer = os.environ.get("ASC_ISSUER_ID", "").strip()
    key_path = os.environ.get("ASC_KEY_PATH", "").strip()
    if not key_id or not issuer or not key_path:
        fail("ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH must be set")
    if not os.path.isfile(key_path):
        fail("key file not found: " + key_path)
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    signing_input = (b64url(json.dumps(header, separators=(",", ":")).encode()) + "."
                     + b64url(json.dumps(payload, separators=(",", ":")).encode()))
    result = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path],
                            input=signing_input.encode(), capture_output=True)
    if result.returncode != 0:
        fail("openssl could not sign with the .p8 key: " + result.stderr.decode().strip())
    return signing_input + "." + b64url(der_to_raw(result.stdout))


class Client:
    def __init__(self):
        self.token = make_token()

    def request(self, method, url):
        if not url.startswith("http"):
            url = API + url
        req = urllib.request.Request(url, method=method, headers={"Authorization": "Bearer " + self.token})
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                body = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            try:
                errors = json.loads(detail).get("errors", [])
                detail = "; ".join("%s: %s" % (e.get("title", ""), e.get("detail", "")) for e in errors) or detail
            except ValueError:
                pass
            hint = ""
            if error.code == 401:
                hint = " (check ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8: the key may be wrong or revoked)"
            elif error.code == 403:
                hint = " (the key's role does not allow this; it must be a Team Key with the Admin role)"
            fail("%s %s -> HTTP %d: %s%s" % (method, url, error.code, detail, hint))
        return json.loads(body) if body else None

    def get_all(self, path, params):
        url = path + "?" + urllib.parse.urlencode(params)
        items = []
        while url:
            page = self.request("GET", url)
            items.extend(page.get("data", []))
            url = (page.get("links") or {}).get("next")
        return items


def normalize_serial(serial):
    return serial.strip().upper().lstrip("0")


def keychain_dev_serials():
    result = subprocess.run(["security", "find-certificate", "-a", "-c", "Apple Development", "-p"],
                            capture_output=True, text=True)
    # Exit status 44 means "not found", i.e. no certificates.
    if result.returncode not in (0, 44):
        fail("security find-certificate failed: " + result.stderr.strip())
    pems = re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", result.stdout, re.S)
    serials = []
    for pem in pems:
        out = subprocess.run(["openssl", "x509", "-noout", "-serial"], input=pem,
                             capture_output=True, text=True, check=True).stdout
        serials.append(normalize_serial(out.split("=", 1)[1]))
    return sorted(set(serials))


def cmd_check(args):
    client = Client()
    devices = client.get_all("/v1/devices", {
        "filter[platform]": "IOS",
        "filter[status]": "ENABLED",
        "fields[devices]": "name,udid,deviceClass,model",
        "limit": "200",
    })
    print("App Store Connect key OK.")
    if not devices:
        fail("no iOS device is registered in Apple Developer (Certificates, IDs & Profiles > Devices); "
             "an Ad Hoc profile needs at least one")
    print("%d enabled iOS device(s):" % len(devices))
    udids = []
    for device in devices:
        attrs = device["attributes"]
        print("  - %s (%s, %s)" % (attrs.get("name"), attrs.get("deviceClass"), attrs.get("model") or "?"))
        if attrs.get("deviceClass") in ("IPHONE", "IPAD", "IPOD"):
            udids.append(attrs["udid"])
    if args.udids_out:
        with open(args.udids_out, "w") as f:
            f.write("".join(u + "\n" for u in udids))


def cmd_dev_serials(_args):
    for serial in keychain_dev_serials():
        print(serial)


def cmd_revoke_new_dev_certs(args):
    if not os.path.exists(args.before):
        # Without the "before" list every certificate would look new: revoke nothing.
        print("No %s (the build stopped before xcodebuild ran); nothing to revoke." % args.before)
        return
    with open(args.before) as f:
        before = {normalize_serial(line) for line in f if line.strip()}
    new = [s for s in keychain_dev_serials() if s not in before]
    if not new:
        print("No new Apple Development certificate in the keychain; nothing to revoke.")
        return
    print("New Apple Development certificate(s) in the keychain: " + ", ".join(new))
    client = Client()
    certificates = client.get_all("/v1/certificates", {
        "filter[certificateType]": DEV_CERT_TYPES,
        "fields[certificates]": "serialNumber,name,certificateType",
        "limit": "200",
    })
    by_serial = {normalize_serial(c["attributes"]["serialNumber"]): c for c in certificates}
    missing = []
    for serial in new:
        certificate = by_serial.get(serial)
        if certificate is None:
            missing.append(serial)
            continue
        client.request("DELETE", "/v1/certificates/" + certificate["id"])
        print("Revoked %s (serial %s)." % (certificate["attributes"].get("name"), serial))
    if missing:
        # Already revoked, or created by another team: nothing left to clean up.
        print("Not found in App Store Connect (already revoked?): " + ", ".join(missing))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    check = sub.add_parser("check", help="validate the key and the registered devices")
    check.add_argument("--udids-out", help="write the iPhone/iPad UDIDs here")
    check.set_defaults(func=cmd_check)
    serials = sub.add_parser("dev-serials", help="serials of the Apple Development certificates in the keychain")
    serials.set_defaults(func=cmd_dev_serials)
    revoke = sub.add_parser("revoke-new-dev-certs", help="revoke the Apple Development certificates created since")
    revoke.add_argument("--before", required=True, help="file written by dev-serials before the build")
    revoke.set_defaults(func=cmd_revoke_new_dev_certs)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
