import django
from django.conf import settings

settings.configure(
    SECRET_KEY="local-test",
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
            "LOCATION": "quoted-public-smuggle",
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
    response = HttpResponse(
        f"smuggle identity={identity}; origin={hits['smuggle']}"
    )
    # Valid extension directive with a quoted-string argument. There is no
    # actual Cache-Control "public" directive here.
    response["Cache-Control"] = 'x-example="a, public, b", max-age=60'
    return response


urlpatterns = [
    path("safe/", safe_view),
    path("smuggle/", smuggle_view),
]

c1 = Client()
c2 = Client()

cache.clear()
s1 = c1.get("/safe/", HTTP_AUTHORIZATION="Bearer user-A")
s2 = c2.get("/safe/", HTTP_AUTHORIZATION="Bearer user-B")

cache.clear()
m1 = c1.get("/smuggle/", HTTP_AUTHORIZATION="Bearer user-A")
m2 = c2.get("/smuggle/", HTTP_AUTHORIZATION="Bearer user-B")

print("Django", django.get_version())
print("safe hits:", hits["safe"])
print("safe first:", s1.content.decode())
print("safe second:", s2.content.decode())
print("safe Vary:", s2.get("Vary"))
print("smuggle hits:", hits["smuggle"])
print("smuggle first:", m1.content.decode())
print("smuggle second:", m2.content.decode())
print("smuggle Vary:", m2.get("Vary"))
print("smuggle Cache-Control:", m2["Cache-Control"])

# Control: without a real public directive, authenticated responses are cached
# separately by Authorization.
assert hits["safe"] == 2
assert s1.content != s2.content
assert "Authorization" in (s2.get("Vary") or "")

# Candidate: "public" exists only inside a quoted extension value. Django's
# current splitter incorrectly treats it as a directive, suppresses
# Vary: Authorization, and reuses user A's cached response for user B.
assert hits["smuggle"] == 1
assert m1.content == b"smuggle identity=Bearer user-A; origin=1"
assert m2.content == m1.content
assert "Authorization" not in (m2.get("Vary") or "")

print("RESULT=REPRODUCED")
print("AUTH_RESULT=CROSS_USER_REPLAY")
