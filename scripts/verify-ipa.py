#!/usr/bin/env python3
"""Checks a signed Ad Hoc IPA (macOS: needs `security` and `codesign`).

    verify-ipa.py App.ipa [--udids FILE]

For every bundle in the IPA (the app and each .appex):
  - embedded.mobileprovision exists, is not expired and lists devices (Ad Hoc);
  - the code signature is valid.
With --udids (one UDID per line, from `asc.py check`), warns about registered
devices missing from a profile.
"""

import argparse
import datetime
import os
import plistlib
import subprocess
import sys
import tempfile
import zipfile


def run(cmd):
    return subprocess.run(cmd, check=True, capture_output=True).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("ipa")
    parser.add_argument("--udids")
    args = parser.parse_args()

    udids = []
    if args.udids and os.path.exists(args.udids):
        with open(args.udids) as f:
            udids = [line.strip() for line in f if line.strip()]

    errors = []
    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(args.ipa) as z:
            z.extractall(tmp)
        bundles = []
        for root, dirs, _ in os.walk(os.path.join(tmp, "Payload")):
            for d in dirs:
                if d.endswith((".app", ".appex")):
                    bundles.append(os.path.join(root, d))
        if not bundles:
            sys.exit("error: no .app in %s" % args.ipa)

        for bundle in sorted(bundles):
            name = os.path.relpath(bundle, tmp)
            with open(os.path.join(bundle, "Info.plist"), "rb") as f:
                bundle_id = plistlib.load(f).get("CFBundleIdentifier")
            print("%s (%s)" % (name, bundle_id))

            profile_path = os.path.join(bundle, "embedded.mobileprovision")
            if not os.path.exists(profile_path):
                errors.append("%s: no embedded.mobileprovision" % name)
                continue
            profile = plistlib.loads(run(["security", "cms", "-D", "-i", profile_path]))
            devices = profile.get("ProvisionedDevices") or []
            expires = profile.get("ExpirationDate")
            print("  profile: %s, team %s, %d device(s), expires %s"
                  % (profile.get("Name"), ",".join(profile.get("TeamIdentifier", [])), len(devices), expires))
            if profile.get("ProvisionsAllDevices"):
                errors.append("%s: enterprise profile, not Ad Hoc" % name)
            if not devices:
                errors.append("%s: the profile lists no devices (not Ad Hoc)" % name)
            if profile.get("Entitlements", {}).get("get-task-allow"):
                errors.append("%s: development profile (get-task-allow), not Ad Hoc" % name)
            if expires and expires.replace(tzinfo=None) < datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
                errors.append("%s: the profile has expired" % name)
            missing = [u for u in udids if u not in devices]
            if missing:
                print("::warning::%s: %d registered device(s) are not in the profile: %s"
                      % (name, len(missing), ", ".join(missing)))

            check = subprocess.run(["codesign", "--verify", "--strict", bundle], capture_output=True, text=True)
            if check.returncode != 0:
                errors.append("%s: invalid code signature: %s" % (name, check.stderr.strip()))

    if errors:
        for e in errors:
            print("error: " + e, file=sys.stderr)
        sys.exit(1)
    print("IPA OK: every bundle is signed Ad Hoc.")


if __name__ == "__main__":
    main()
