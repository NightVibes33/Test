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
    # Valid extension directive with a quoted comma-containing value and no
    # occurrence of the token/string "public".
    response["Cache-Control"] = 'x-example="foo, harmless, bar", max-age=60'
    return response

def candidate_view(request):
    hits["candidate"] += 1
    identity = request.headers.get("Authorization", "none")
    response = HttpResponse(f"candidate identity={identity}; origin={hits['candidate']}")
    # "public" is data inside an extension directive's quoted-string value,
    # not a top-level Cache-Control directive.
    response["Cache-Control"] = 'x-example="foo, public, bar", max-age=60'
    return response

urlpatterns = [
    path("control/", control_view),
    path("candidate/", candidate_view),
]

def get(path, identity):
    client = Client()
    return client.get(path, HTTP_AUTHORIZATION=f"Bearer {identity}")

cache.clear()
control_a = get("/control/", "user-A")
control_b = get("/control/", "user-B")

print("Django", django.get_version())
print("control hits:", hits["control"])
print("control A:", control_a.content.decode())
print("control B:", control_b.content.decode())
print("control Vary A:", control_a.get("Vary"))
print("control Vary B:", control_b.get("Vary"))
print("control Cache-Control:", control_a.get("Cache-Control"))

assert hits["control"] == 2
assert b"user-A" in control_a.content
assert b"user-B" in control_b.content
assert "Authorization" in (control_a.get("Vary") or "")
assert "Authorization" in (control_b.get("Vary") or "")

cache.clear()
candidate_a = get("/candidate/", "user-A")
candidate_b = get("/candidate/", "user-B")

print("candidate hits:", hits["candidate"])
print("candidate A:", candidate_a.content.decode())
print("candidate B:", candidate_b.content.decode())
print("candidate Vary A:", candidate_a.get("Vary"))
print("candidate Vary B:", candidate_b.get("Vary"))
print("candidate Cache-Control:", candidate_a.get("Cache-Control"))

assert hits["candidate"] == 1, hits
assert b"user-A" in candidate_a.content
assert candidate_b.content == candidate_a.content
assert b"user-A" in candidate_b.content
assert b"user-B" not in candidate_b.content
assert "Authorization" not in (candidate_a.get("Vary") or "")
assert "Authorization" not in (candidate_b.get("Vary") or "")

print("RESULT=REPRODUCED")
print("CROSS_USER_AUTH_CACHE_REPLAY=YES")
