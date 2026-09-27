# Big-endian HEXEWKB bypasses GeoDjango GeometryCollection depth limit and can crash GEOS

## Summary

Django's mitigation for CVE-2026-15830 can be bypassed with big-endian HEXEWKB that uses EWKB flags such as the SRID flag.

The new `_WKBReader.limit_hex()` limiter parses the hexadecimal type field with `int(..., 16)` and then unconditionally byte-swaps the resulting 32-bit value. That is correct for little-endian WKB (`01`) but incorrect for big-endian WKB (`00`), where the parsed integer is already in the correct order.

For plain big-endian WKB, the current implementation can accidentally find shifted byte windows that look like little-endian GeometryCollection headers, masking the bug. Adding a normal EWKB flag/field (for example, SRID) removes those false-positive windows.

As a result, valid big-endian HEXEWKB containing arbitrarily deep nested GeometryCollections can pass `max_geom_collections` and reach GEOS. On GEOS versions without their own recursion-depth protection, this causes a stack-exhaustion segmentation fault.

This is a follow-up bypass of CVE-2026-15830.

## Affected code

`django/contrib/gis/geos/prototypes/io.py`, `_WKBReader.limit_hex()`:

```python
byte_order = wkb[index : index + 2]
if byte_order not in (b"00", b"01"):
    continue
try:
    geometry_type = int(wkb[index + 2 : index + 10], 16)
except ValueError:
    continue
geometry_type = _byteswap_uint32(geometry_type)
if (geometry_type & 0xFFFF) % 1000 == 7:
    ...
```

For byte order `00`, the unconditional swap is wrong.

## Confirmed affected targets

- Django 6.1.1
- Django current main / 6.2-dev at commit `9e06baf2e4dd17834b5deaf3a3e6ae3bff2fcf26`
- The same vulnerable `limit_hex()` implementation is present in `stable/6.0.x`
- The same vulnerable `limit_hex()` implementation is present in `stable/5.2.x`

## Reproduction

PoC branch:

`NightVibes33/Test:h1-django-geos-big-endian-ewkb-limit-bypass`

PoC:

`django-geos-big-endian-ewkb-limit-bypass.py`

Workflow:

`.github/workflows/django-geos-big-endian-ewkb-limit-bypass.yml`

### Small deterministic bypass

The PoC constructs equivalent nested EWKB values.

Expected controls:

```
little-endian hex str: blocked=True
big-endian binary memoryview: blocked=True
```

Vulnerable big-endian HEXEWKB behavior:

```
big-endian hex str: blocked=False result=GeometryCollection
big-endian hex bytes: blocked=False result=GeometryCollection
GeometryField.clean(big-endian hex): blocked=False result=GeometryCollection
```

The same geometry that is blocked as binary WKB therefore bypasses the limiter when represented as a big-endian HEXEWKB string.

### Process-level DoS proof

The PoC then invokes the public GeoDjango form parsing path in an isolated subprocess:

```python
GeometryField(max_geom_collections=198).clean(payload)
```

The payload contains 100,000 nested GeometryCollections encoded as big-endian HEXEWKB with the EWKB SRID flag.

On Django 6.1.1 with GEOS 3.12.1:

```
Django=6.1.1 GEOS=3.12.1-CAPI-1.18.1
VULNERABLE: big-endian hex EWKB bypassed max_geom_collections
GeometryField.clean(big-endian hex): blocked=False result=GeometryCollection
child: Django=6.1.1 GEOS=3.12.1-CAPI-1.18.1 depth=100000 hex_bytes=2600050
child_returncode=-11
DOS_CONFIRMED: GeometryField.clean() can reach a fatal GEOS path
```

`-11` is SIGSEGV.

The same direct crash was also confirmed on current Django main / 6.2-dev with GEOS 3.12.1.

## Why this bypasses the CVE-2026-15830 fix

CVE-2026-15830 introduced a limit of 198 GeometryCollections specifically to reject deeply nested input before GEOS parses it.

For HEXEWKB, Django scans candidate headers and normalizes the type field. The hexadecimal byte sequence already preserves WKB byte order:

- `01 07 00 00 00`: little-endian GeometryCollection; parsed integer needs byte-swapping.
- `00 00 00 00 07`: big-endian GeometryCollection; parsed integer is already `7` and must not be byte-swapped.

Current code swaps both forms.

With big-endian EWKB SRID headers such as:

```
00 20 00 00 07 <srid> 00 00 00 01
```

the scanner does not count the actual GeometryCollection headers and the nested input reaches GEOS unbounded.

## Security impact

An application accepting attacker-controlled geometry input through GeoDjango's `GeometryField`, model geometry preparation, spatial lookup paths, or direct `GEOSGeometry` construction can receive a HEXEWKB string that bypasses Django's recursion limiter.

On affected GEOS releases, a sufficiently deep payload exhausts the native stack and terminates the worker process with SIGSEGV.

This restores the denial-of-service condition that CVE-2026-15830 was intended to prevent.

## Suggested fix

Honor the WKB byte-order marker when decoding the hexadecimal type field:

```diff
- geometry_type = _byteswap_uint32(geometry_type)
+ if byte_order == b"01":
+     geometry_type = _byteswap_uint32(geometry_type)
```

Add a regression test using big-endian HEXEWKB with the SRID flag, because the existing plain big-endian WKB test can be masked by shifted false-positive header matches.

A proposed fix and regression-test diff is included in:

`django-geos-big-endian-ewkb-proposed-fix.diff`

## Suggested weakness / severity

- Weakness: CWE-400 (Uncontrolled Resource Consumption) / denial of service via stack exhaustion
- Suggested severity: Medium, consistent with the original CVE-2026-15830 classification as moderate
