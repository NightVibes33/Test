import threading

import django
from django.conf import settings

settings.configure(
    SECRET_KEY="local-vary-race-test",
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
            "LOCATION": "vary-registry-race",
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
from django.middleware.cache import CacheMiddleware
from django.test import RequestFactory
from django.utils.cache import _generate_cache_key
from django.utils.cache import patch_vary_headers


factory = RequestFactory()
hits = {"region": 0, "tenant": 0}


def view(request):
    if request.headers.get("X-Region") is not None:
        hits["region"] += 1
        response = HttpResponse(
            f"REGION-REPRESENTATION:{request.headers['X-Region']}:origin={hits['region']}"
        )
        patch_vary_headers(response, ("X-Region",))
        return response

    if request.headers.get("X-Tenant") is not None:
        hits["tenant"] += 1
        response = HttpResponse(
            f"TENANT-REPRESENTATION:{request.headers['X-Tenant']}:origin={hits['tenant']}"
        )
        patch_vary_headers(response, ("X-Tenant",))
        return response

    return HttpResponse("default")


middleware = CacheMiddleware(view)
cache.clear()

# Both requests use the same opaque value under different Vary header names.
# Django 6.1.1/current main hashes only values, so these page keys collide.
request_a_for_key = factory.get("/resource/", HTTP_X_REGION="scope-123")
request_b_for_key = factory.get("/resource/", HTTP_X_TENANT="scope-123")
key_a = _generate_cache_key(
    request_a_for_key, "GET", ["HTTP_X_REGION"], ""
)
key_b = _generate_cache_key(
    request_b_for_key, "GET", ["HTTP_X_TENANT"], ""
)

print("Django", django.get_version())
print("key A:", key_a)
print("key B:", key_b)
print("same key:", key_a == key_b)
assert key_a == key_b, "Expected current Django to collide across header names."

original_set = cache.set
a_header_written = threading.Event()
b_page_written = threading.Event()
errors = []


def controlled_set(key, value, timeout=None, version=None):
    is_header_registry = ".cache_header." in key
    is_page = ".cache_page." in key
    name = threading.current_thread().name

    if name == "A" and is_header_registry:
        # Publish A's learned Vary list, then pause before learn_cache_key()
        # returns and A writes its page object.
        result = original_set(key, value, timeout, version)
        a_header_written.set()
        if not b_page_written.wait(5):
            raise RuntimeError("Timed out waiting for B page write")
        return result

    if name == "B" and is_page:
        result = original_set(key, value, timeout, version)
        b_page_written.set()
        return result

    return original_set(key, value, timeout, version)


cache.set = controlled_set


def run_a():
    try:
        request = factory.get("/resource/", HTTP_X_REGION="scope-123")
        response = middleware(request)
        print("A response:", response.content.decode())
        print("A Vary:", response.get("Vary"))
    except Exception as exc:
        errors.append(("A", repr(exc)))


def run_b():
    try:
        if not a_header_written.wait(5):
            raise RuntimeError("Timed out waiting for A header registry write")
        request = factory.get("/resource/", HTTP_X_TENANT="scope-123")
        response = middleware(request)
        print("B response:", response.content.decode())
        print("B Vary:", response.get("Vary"))
    except Exception as exc:
        errors.append(("B", repr(exc)))


ta = threading.Thread(target=run_a, name="A")
tb = threading.Thread(target=run_b, name="B")
ta.start()
tb.start()
ta.join(10)
tb.join(10)

if ta.is_alive() or tb.is_alive():
    raise RuntimeError("Worker thread did not finish")
if errors:
    raise RuntimeError(errors)

# Restore the normal cache method before the victim request.
cache.set = original_set

# Expected final state from the forced legitimate interleaving:
# 1. A writes registry = [HTTP_X_REGION] and pauses.
# 2. B writes registry = [HTTP_X_TENANT], then page K = B.
# 3. A resumes and writes page K = A.
# So the registry says "key on X-Tenant", but K contains A's X-Region response.
victim = factory.get("/resource/", HTTP_X_TENANT="scope-123")
victim_response = middleware(victim)

print("origin hits:", hits)
print("victim body:", victim_response.content.decode())
print("victim Vary:", victim_response.get("Vary"))

assert hits == {"region": 1, "tenant": 1}, (
    "Victim unexpectedly reached the origin instead of the poisoned cache state."
)
assert victim_response.content == b"REGION-REPRESENTATION:scope-123:origin=1"
assert victim_response.get("Vary") == "X-Region"

print("RESULT=REPRODUCED")
print("CACHE_REGISTRY_PAGE_RACE=CROSS_CONTEXT_REPLAY")
