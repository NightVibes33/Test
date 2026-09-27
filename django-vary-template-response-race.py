import django
from django.conf import settings

settings.configure(
    SECRET_KEY="local-vary-template-race-test",
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
            "LOCATION": "vary-template-response-race",
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
from django.middleware.cache import CacheMiddleware
from django.template.response import SimpleTemplateResponse
from django.test import RequestFactory
from django.utils.cache import _generate_cache_key, patch_vary_headers


class TinyTemplate:
    def render(self, context=None, request=None):
        return context["body"]


factory = RequestFactory()
hits = {"region": 0, "tenant": 0}


def view(request):
    if request.headers.get("X-Region") is not None:
        hits["region"] += 1
        response = SimpleTemplateResponse(
            TinyTemplate(),
            {
                "body": (
                    f"REGION-REPRESENTATION:{request.headers['X-Region']}:"
                    f"origin={hits['region']}"
                )
            },
        )
        patch_vary_headers(response, ("X-Region",))
        return response

    if request.headers.get("X-Tenant") is not None:
        hits["tenant"] += 1
        response = SimpleTemplateResponse(
            TinyTemplate(),
            {
                "body": (
                    f"TENANT-REPRESENTATION:{request.headers['X-Tenant']}:"
                    f"origin={hits['tenant']}"
                )
            },
        )
        patch_vary_headers(response, ("X-Tenant",))
        return response

    return SimpleTemplateResponse(TinyTemplate(), {"body": "default"})


middleware = CacheMiddleware(view)
cache.clear()

request_a_key = factory.get("/resource/", HTTP_X_REGION="scope-123")
request_b_key = factory.get("/resource/", HTTP_X_TENANT="scope-123")
key_a = _generate_cache_key(request_a_key, "GET", ["HTTP_X_REGION"], "")
key_b = _generate_cache_key(request_b_key, "GET", ["HTTP_X_TENANT"], "")

print("Django", django.get_version())
print("key A:", key_a)
print("key B:", key_b)
print("same key:", key_a == key_b)
assert key_a == key_b

# This models two concurrent requests reaching the response-middleware phase
# before either TemplateResponse finishes rendering.
#
# Request A:
#   learn_cache_key() stores [HTTP_X_REGION].
#   CacheMiddleware defers page write A until A.render().
response_a = middleware(factory.get("/resource/", HTTP_X_REGION="scope-123"))
assert not response_a.is_rendered

# Request B arrives while A is still rendering:
#   Fetch sees A's registry but no cached page yet, so B reaches the origin.
#   learn_cache_key() replaces the registry with [HTTP_X_TENANT].
#   Page write B is likewise deferred until B.render().
response_b = middleware(factory.get("/resource/", HTTP_X_TENANT="scope-123"))
assert not response_b.is_rendered

print("pre-render hits:", hits)
assert hits == {"region": 1, "tenant": 1}

# B finishes first and caches its response under K.
response_b.render()
print("B rendered:", response_b.content.decode())

# A finishes later and overwrites K with A's response. The global registry,
# however, remains B's [HTTP_X_TENANT].
response_a.render()
print("A rendered:", response_a.content.decode())

# A subsequent X-Tenant request is keyed according to B's registry, but K now
# contains A's X-Region representation. It is served from cache and does not
# reach the origin.
victim = middleware(factory.get("/resource/", HTTP_X_TENANT="scope-123"))

print("final hits:", hits)
print("victim body:", victim.content.decode())
print("victim Vary:", victim.get("Vary"))

assert hits == {"region": 1, "tenant": 1}
assert victim.content == b"REGION-REPRESENTATION:scope-123:origin=1"
assert victim.get("Vary") == "X-Region"

print("RESULT=REPRODUCED")
print("TEMPLATE_RESPONSE_RACE=CROSS_CONTEXT_REPLAY")
