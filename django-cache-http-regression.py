import http.client
import threading

import django
from django.conf import settings

settings.configure(
    SECRET_KEY="local-test",
    DEBUG=False,
    ALLOWED_HOSTS=["127.0.0.1", "localhost"],
    ROOT_URLCONF=__name__,
    MIDDLEWARE=[
        "django.middleware.cache.UpdateCacheMiddleware",
        "django.middleware.cache.FetchFromCacheMiddleware",
    ],
    CACHES={
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "raw-set-cookie-http-test",
        }
    },
    CACHE_MIDDLEWARE_ALIAS="default",
    CACHE_MIDDLEWARE_SECONDS=60,
    CACHE_MIDDLEWARE_KEY_PREFIX="",
    USE_I18N=False,
    USE_TZ=False,
)
django.setup()

from django.core.wsgi import get_wsgi_application
from django.http import HttpResponse
from django.urls import path
from django.utils.cache import patch_vary_headers
from wsgiref.simple_server import make_server

hits = {"raw": 0, "normal": 0}


def raw_view(request):
    hits["raw"] += 1
    response = HttpResponse(f"raw-origin-{hits['raw']}")
    response["Set-Cookie"] = "example=value; Path=/; HttpOnly"
    patch_vary_headers(response, ("Cookie",))
    return response


def normal_view(request):
    hits["normal"] += 1
    response = HttpResponse(f"normal-origin-{hits['normal']}")
    response.set_cookie("example", "value", httponly=True)
    patch_vary_headers(response, ("Cookie",))
    return response


urlpatterns = [
    path("raw/", raw_view),
    path("normal/", normal_view),
]

application = get_wsgi_application()
server = make_server("127.0.0.1", 0, application)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
port = server.server_port


def request(path):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    conn.request("GET", path)
    response = conn.getresponse()
    body = response.read().decode()
    headers = dict(response.getheaders())
    conn.close()
    return response.status, headers, body


try:
    n1 = request("/normal/")
    n2 = request("/normal/")
    r1 = request("/raw/")
    r2 = request("/raw/")
finally:
    server.shutdown()
    thread.join(timeout=5)

print("Django", django.get_version())
print("normal hits:", hits["normal"])
print("normal responses:", n1, n2)
print("raw hits:", hits["raw"])
print("raw first:", r1)
print("raw second:", r2)

assert hits["normal"] == 2
assert hits["raw"] == 1
assert r1[1].get("Set-Cookie") == "example=value; Path=/; HttpOnly"
assert r2[1].get("Set-Cookie") == r1[1].get("Set-Cookie")
assert r2[2] == r1[2] == "raw-origin-1"

print("HTTP_RESULT=REPRODUCED")
