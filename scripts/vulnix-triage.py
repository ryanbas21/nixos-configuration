#!/usr/bin/env python3
"""vulnix triage helper — NVD descriptions + CPE ranges for CVE ids.

Fetches the NVD 2.0 record for each CVE (cached under
~/.cache/vulnix-triage) and prints its description, CVSS, and — the
part that settles false positives in seconds — every NVD CPE node
(vendor:product + version range). With repeatable `--pin name=version`
flags, nodes whose product matches a pin also get an
affected / not-affected verdict against that version, so name
collisions (jenkins:git vs git, diff_project:diff vs Haskell Diff)
and out-of-range date-bound CPEs (`gnu:gcc <2023-09-12`) are visible
at a glance.

Usage (the whitelist triage ritual is docs/programs/security.md):

    just triage-vulnix CVE-2026-89161 CVE-2026-89162
    python3 scripts/vulnix-triage.py --pin curl=8.21.0 --pin openssl=3.6.3 \\
        CVE-2026-19931 CVE-2026-18924

Version comparison is numeric per dot/ dash-separated component, with
a lexical fallback for non-numeric tails (openssl's 1.0.2zr, gcc's
date bounds); unparseable comparisons are reported as `?` rather than
guessed. Exposure (the other half of triage) is not this script's
job: `nix why-depends <toplevel> <out-path>` answers it.

The anonymous NVD API allows 5 requests / 30 s — the script sleeps
between fetches. `--refresh` bypasses the cache: NVD enriches CPE
data days after publication, which is exactly how the 2026-09-20
drift batch surfaced (CVEs published 08-25, CPE nodes added later).
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.request

NVD_API = "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId="
CACHE_DIR = os.path.expanduser("~/.cache/vulnix-triage")


def fetch(cve: str, refresh: bool) -> dict:
    os.makedirs(CACHE_DIR, exist_ok=True)
    path = os.path.join(CACHE_DIR, f"{cve}.json")
    if not refresh and os.path.exists(path) and os.path.getsize(path) > 0:
        with open(path) as f:
            return json.load(f)
    for attempt in range(3):
        req = urllib.request.Request(NVD_API + cve, headers={"User-Agent": "vulnix-triage"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                data = json.load(r)
            with open(path, "w") as f:
                json.dump(data, f)
            time.sleep(6.5)  # anonymous NVD budget: 5 requests / 30 s
            return data
        except Exception as e:  # noqa: BLE001 — report and retry/backoff
            if attempt == 2:
                print(f"{cve}: fetch failed after 3 attempts: {e}", file=sys.stderr)
                return {}
            time.sleep(10 * (attempt + 1))
    return {}


def vtuple(version: str):
    out = []
    for part in re.split(r"[.\-]", str(version)):
        if part.isdigit():
            out.append(int(part))
        else:
            break  # lexical tail (1.0.2zr, 2023-09-12 vs 9.0.1): stop comparing
    return out


def vcmp(a: str, b: str):
    """-1/0/1, or None when a/b are not numerically comparable."""
    ta, tb = vtuple(a), vtuple(b)
    if not ta or not tb:
        return None
    for i in range(max(len(ta), len(tb))):
        x = ta[i] if i < len(ta) else 0
        y = tb[i] if i < len(tb) else 0
        if x != y:
            return -1 if x < y else 1
    return 0


def node_ranges(cpe: dict) -> str:
    parts = []
    if "versionStartExcluding" in cpe:
        parts.append(f"> (excl) {cpe['versionStartExcluding']}")
    if "versionStartIncluding" in cpe:
        parts.append(f">= {cpe['versionStartIncluding']}")
    if "versionEndExcluding" in cpe:
        parts.append(f"< (excl) {cpe['versionEndExcluding']}")
    if "versionEndIncluding" in cpe:
        parts.append(f"<= {cpe['versionEndIncluding']}")
    if parts:
        return ", ".join(parts)
    version = cpe["criteria"].split(":")[4]
    return f"== {version}" if version not in ("", "*", "-") else "ALL versions"


def verdict(cpe: dict, ours: str) -> str:
    checks = []
    if "versionStartExcluding" in cpe:
        checks.append((vcmp(ours, cpe["versionStartExcluding"]), ">", 0))
    if "versionStartIncluding" in cpe:
        checks.append((vcmp(ours, cpe["versionStartIncluding"]), ">=", 0))
    if "versionEndExcluding" in cpe:
        checks.append((vcmp(ours, cpe["versionEndExcluding"]), "<", 0))
    if "versionEndIncluding" in cpe:
        checks.append((vcmp(ours, cpe["versionEndIncluding"]), "<=", 0))
    if not checks:
        version = cpe["criteria"].split(":")[4]
        if version in ("", "*", "-"):
            return "AFFECTED (unbounded)"
        c = vcmp(ours, version)
        return "AFFECTED (exact)" if c == 0 else ("not-affected" if c is not None else "?")
    if any(c is None for c, _op, _v in checks):
        return "? (non-numeric bound)"
    if all((c > 0 if op == ">" else c >= 0 if op == ">=" else c < 0 if op == "<" else c <= 0) for c, op, _v in checks):
        return "AFFECTED"
    return "not-affected"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cves", nargs="+", help="CVE ids, e.g. CVE-2026-89161")
    ap.add_argument(
        "--pin",
        action="append",
        default=[],
        metavar="name=version",
        help="derivation name + version to verdict against (repeatable); "
        "matches CPE products by exact name or name prefix (pcre2-10.47 --pin pcre2=10.47)",
    )
    ap.add_argument("--refresh", action="store_true", help="bypass the local NVD cache")
    args = ap.parse_args()

    pins = {}
    for p in args.pin:
        if "=" not in p:
            ap.error(f"--pin expects name=version, got {p!r}")
        name, version = p.split("=", 1)
        pins[name] = version
    if pins:
        print(f"pins: {', '.join(f'{k}={v}' for k, v in pins.items())}\n")

    rc = 0
    for cve in args.cves:
        if not re.fullmatch(r"CVE-\d{4}-\d+", cve):
            print(f"===== {cve}: not a CVE id, skipped", file=sys.stderr)
            rc = 1
            continue
        d = fetch(cve, args.refresh)
        vulns = d.get("vulnerabilities", [])
        if not vulns:
            print(f"===== {cve}: NOT FOUND IN NVD\n")
            rc = 1
            continue
        c = vulns[0]["cve"]
        desc = next((x["value"] for x in c["descriptions"] if x["lang"] == "en"), "")
        cvss = ""
        for key in ("cvssMetricV31", "cvssMetricV30", "cvssMetricV2"):
            if c.get("metrics", {}).get(key):
                m = c["metrics"][key][0]
                cvss = f"{m['cvssData'].get('baseScore', '?')} {m['cvssData'].get('vectorString', '')}"
                break
        print(f"===== {cve} (published {c.get('published', '?')[:10]})  CVSS {cvss}")
        print("\n".join(f"  {l}" for l in re.findall(r".{1,100}(?:\s|$)", desc.strip())[:6]))
        seen = set()
        for conf in c.get("configurations", []):
            for node in conf.get("nodes", []):
                for cpe in node.get("cpeMatch", []):
                    m = re.match(r"cpe:2\.3:[a-z]:([^:]+):([^:]+)", cpe.get("criteria", ""))
                    if not m:
                        continue
                    vendor, product = m.groups()
                    line = f"{vendor}:{product} {node_ranges(cpe)}"
                    if line in seen:
                        continue
                    seen.add(line)
                    pin = pins.get(product) or next((v for k, v in pins.items() if product.startswith(k + "-")), None)
                    if pin:
                        line += f"  << ours {product}={pin}: {verdict(cpe, pin)}"
                    print(f"  CPE {line}")
        print()
    return rc


if __name__ == "__main__":
    sys.exit(main())
