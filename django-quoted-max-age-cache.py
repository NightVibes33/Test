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
            "LOCATION": "quoted-max-age-test",
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

hits = {"token": 0, "quoted": 0, "auth": 0}


def token_view(request):
    hits["token"] += 1
    response = HttpResponse(f"token-origin-{hits['token']}")
    response["Cache-Control"] = "max-age=0"
    return response


def quoted_view(request):
    hits["quoted"] += 1
    response = HttpResponse(f"quoted-origin-{hits['quoted']}")
    response["Cache-Control"] = 'max-age="0"'
    return response


def auth_view(request):
    hits["auth"] += 1
    identity = request.headers.get("Authorization", "none")
    response = HttpResponse(f"identity={identity}; origin={hits['auth']}")
    response["Cache-Control"] = 'public, max-age="0"'
    return response


urlpatterns = [
    path("token/", token_view),
    path("quoted/", quoted_view),
    path("auth/", auth_view),
]

cache.clear()
c1 = Client()
c2 = Client()

t1 = c1.get("/token/")
t2 = c2.get("/token/")

cache.clear()
q1 = c1.get("/quoted/")
q2 = c2.get("/quoted/")

cache.clear()
a1 = c1.get("/auth/", HTTP_AUTHORIZATION="Bearer user-A")
a2 = c2.get("/auth/", HTTP_AUTHORIZATION="Bearer user-B")

print("Django", django.get_version())
print("token hits:", hits["token"])
print("token responses:", t1.content.decode(), t2.content.decode())
print("token Cache-Control:", t2["Cache-Control"])
print("quoted hits:", hits["quoted"])
print("quoted responses:", q1.content.decode(), q2.content.decode())
print("quoted Cache-Control:", q2["Cache-Control"])
print("auth hits:", hits["auth"])
print("auth first:", a1.content.decode())
print("auth second:", a2.content.decode())
print("auth Vary:", a2.get("Vary"))
print("auth Cache-Control:", a2["Cache-Control"])

assert hits["token"] == 2, "Control max-age=0 should not be cached."
assert t1.content != t2.content

assert hits["quoted"] == 1, 'Quoted max-age="0" unexpectedly was not cached.'
assert q1.content == q2.content == b"quoted-origin-1"
assert "max-age=60" in q2["Cache-Control"], q2["Cache-Control"]

assert hits["auth"] == 1, "Second authenticated request unexpectedly reached origin."
assert a1.content == b"identity=Bearer user-A; origin=1"
assert a2.content == a1.content
assert a2.get("Vary") != "Authorization"
assert "max-age=60" in a2["Cache-Control"], a2["Cache-Control"]

print("RESULT=REPRODUCED")
print('Quoted max-age="0" was treated as absent and replaced by the 60-second cache timeout.')
print("AUTH_RESULT=CROSS_USER_REPLAY")
print("A user-B Authorization request received the cached user-A authenticated response.")
