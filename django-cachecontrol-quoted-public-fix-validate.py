import django.utils.http as http_utils

def quote_aware_split_header_value(value, sep=","):
    if len(sep) != 1:
        for part in value.split(sep):
            if stripped := part.strip():
                yield stripped
        return
    start = 0
    in_quote = False
    escaped = False
    for index, char in enumerate(value):
        if escaped:
            escaped = False
        elif in_quote and char == "\\":
            escaped = True
        elif char == '"':
            in_quote = not in_quote
        elif char == sep and not in_quote:
            if stripped := value[start:index].strip():
                yield stripped
            start = index + 1
    if stripped := value[start:].strip():
        yield stripped

http_utils.split_header_value = quote_aware_split_header_value

assert list(
    http_utils.split_directive_names(
        'x-example="foo, public, bar", max-age=60'
    )
) == ["x-example", "max-age"]
assert list(http_utils.split_directive_names('public="abc"')) == ["public"]

from django.conf import settings

settings.configure(
    SECRET_KEY="fixed-parser-test",
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
            "LOCATION": "quoted-public-fixed-parser",
        }
    },
    CACHE_MIDDLEWARE_ALIAS="default",
    CACHE_MIDDLEWARE_SECONDS=60,
    CACHE_MIDDLEWARE_KEY_PREFIX="",
    USE_I18N=False,
    USE_TZ=False,
)
import django
django.setup()

from django.core.cache import cache
from django.http import HttpResponse
from django.test import Client
from django.urls import path

hits = {"candidate": 0, "real_public": 0}

def candidate_view(request):
    hits["candidate"] += 1
    identity = request.headers.get("Authorization", "none")
    return HttpResponse(
        f"candidate identity={identity}; origin={hits['candidate']}",
        headers={"Cache-Control": 'x-example="foo, public, bar", max-age=60'},
    )

def real_public_view(request):
    hits["real_public"] += 1
    identity = request.headers.get("Authorization", "none")
    return HttpResponse(
        f"real-public identity={identity}; origin={hits['real_public']}",
        headers={"Cache-Control": 'public="abc", max-age=60'},
    )

urlpatterns = [
    path("candidate/", candidate_view),
    path("real-public/", real_public_view),
]

def get(path, identity):
    return Client().get(path, HTTP_AUTHORIZATION=f"Bearer {identity}")

cache.clear()
a = get("/candidate/", "user-A")
b = get("/candidate/", "user-B")
print("candidate hits:", hits["candidate"])
print("candidate Vary A:", a.get("Vary"))
print("candidate Vary B:", b.get("Vary"))
print("candidate A:", a.content.decode())
print("candidate B:", b.content.decode())
assert hits["candidate"] == 2
assert "Authorization" in (a.get("Vary") or "")
assert "Authorization" in (b.get("Vary") or "")
assert b"user-A" in a.content
assert b"user-B" in b.content

cache.clear()
p1 = get("/real-public/", "user-A")
p2 = get("/real-public/", "user-B")
print("real public hits:", hits["real_public"])
print("real public Vary:", p2.get("Vary"))
assert hits["real_public"] == 1
assert "Authorization" not in (p2.get("Vary") or "")
assert p2.content == p1.content
print("FIX_VALIDATION=PASS")
