import django
from django.conf import settings

settings.configure(
    SECRET_KEY="local-cache-control-test",
    DEBUG=False,
    ALLOWED_HOSTS=["testserver"],
    ROOT_URLCONF=__name__,
    MIDDLEWARE=[
        "django.middleware.cache.UpdateCacheMiddleware",
        "django.middleware.cache.FetchFromCacheMiddleware",
    ],
    CACHES={
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "quoted-public-auth-test",
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
from django.http import HttpResponse
from django.test import Client
from django.urls import path

hits = {"control": 0, "candidate": 0}

def control_view(request):
    hits["control"] += 1
    identity = request.headers.get("Authorization", "none")
    response = HttpResponse(f"control identity={identity}; origin={hits['control']}")
    response["Cache-Control"] = 'x-example="foo, harmless, bar", max-age=60'
    return response

def candidate_view(request):
    hits["candidate"] += 1
    identity = request.headers.get("Authorization", "none")
    response = HttpResponse(f"candidate identity={identity}; origin={hits['candidate']}")
    response["Cache-Control"] = 'x-example="foo, public, bar", max-age=60'
    return response

urlpatterns = [
    path("control/", control_view),
    path("candidate/", candidate_view),
]

def authenticated_get(path, identity):
    return Client().get(path, HTTP_AUTHORIZATION=f"Bearer {identity}")

def anonymous_get(path):
    return Client().get(path)

cache.clear()
control_a = authenticated_get("/control/", "user-A")
control_anon = anonymous_get("/control/")

print("Django", django.get_version())
print("control hits:", hits["control"])
print("control A:", control_a.content.decode())
print("control anonymous:", control_anon.content.decode())
print("control Vary A:", control_a.get("Vary"))
print("control anonymous Vary:", control_anon.get("Vary"))
print("control Cache-Control:", control_a.get("Cache-Control"))

assert hits["control"] == 2
assert b"user-A" in control_a.content
assert b"none" in control_anon.content
assert control_anon.content != control_a.content
assert "Authorization" in (control_a.get("Vary") or "")

cache.clear()
candidate_a = authenticated_get("/candidate/", "user-A")
candidate_anon = anonymous_get("/candidate/")

print("candidate hits:", hits["candidate"])
print("candidate A:", candidate_a.content.decode())
print("candidate anonymous:", candidate_anon.content.decode())
print("candidate Vary A:", candidate_a.get("Vary"))
print("candidate anonymous Vary:", candidate_anon.get("Vary"))
print("candidate Cache-Control:", candidate_a.get("Cache-Control"))

assert hits["candidate"] == 1, hits
assert b"user-A" in candidate_a.content
assert candidate_anon.content == candidate_a.content
assert b"user-A" in candidate_anon.content
assert b"none" not in candidate_anon.content
assert "Authorization" not in (candidate_a.get("Vary") or "")

print("RESULT=REPRODUCED")
print("UNAUTHENTICATED_PRIVATE_RESPONSE_REPLAY=YES")
