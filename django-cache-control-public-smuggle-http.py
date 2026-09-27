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
            "LOCATION": "quoted-public-smuggle-http",
        }
    },
    CACHE_MIDDLEWARE_ALIAS="default",
    CACHE_MIDDLEWARE_SECONDS=60,
    CACHE_MIDDLEWARE_KEY_PREFIX="",
    USE_I18N=False,
    USE_TZ=False,
)
django.setup()

from django.core.cache import cache
from django.core.wsgi import get_wsgi_application
from django.http import HttpResponse
from django.urls import path
from wsgiref.simple_server import make_server

hits = {"safe": 0, "smuggle": 0}


def safe_view(request):
    hits["safe"] += 1
    identity = request.headers.get("Authorization", "none")
    response = HttpResponse(f"safe identity={identity}; origin={hits['safe']}")
    response["Cache-Control"] = "x-example=a, max-age=60"
    return response


def smuggle_view(request):
    hits["smuggle"] += 1
    identity = request.headers.get("Authorization", "none")
    response = HttpResponse(f"smuggle identity={identity}; origin={hits['smuggle']}")
    response["Cache-Control"] = 'x-example="a, public, b", max-age=60'
    return response


urlpatterns = [
    path("safe/", safe_view),
    path("smuggle/", smuggle_view),
]

application = get_wsgi_application()
server = make_server("127.0.0.1", 0, application)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
port = server.server_port


def get(path, authorization):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    conn.request("GET", path, headers={"Authorization": authorization})
    response = conn.getresponse()
    body = response.read().decode()
    headers = dict(response.getheaders())
    conn.close()
    return response.status, headers, body


try:
    cache.clear()
    s1 = get("/safe/", "Bearer user-A")
    s2 = get("/safe/", "Bearer user-B")

    cache.clear()
    m1 = get("/smuggle/", "Bearer user-A")
    m2 = get("/smuggle/", "Bearer user-B")
finally:
    server.shutdown()
    thread.join(timeout=5)

print("Django", django.get_version())
print("safe hits:", hits["safe"])
print("safe first body:", s1[2])
print("safe second body:", s2[2])
print("safe Vary:", s2[1].get("Vary"))
print("smuggle hits:", hits["smuggle"])
print("smuggle first body:", m1[2])
print("smuggle second body:", m2[2])
print("smuggle Vary:", m2[1].get("Vary"))
print("smuggle Cache-Control:", m2[1].get("Cache-Control"))

assert hits["safe"] == 2
assert s1[2] != s2[2]
assert "Authorization" in (s2[1].get("Vary") or "")

assert hits["smuggle"] == 1
assert "user-A" in m1[2]
assert m2[2] == m1[2]
assert "user-B" not in m2[2]
assert "Authorization" not in (m2[1].get("Vary") or "")

print("HTTP_RESULT=REPRODUCED")
print("HTTP_AUTH_RESULT=CROSS_USER_REPLAY")
