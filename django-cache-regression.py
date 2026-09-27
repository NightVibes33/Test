import django
from django.conf import settings

settings.configure(
    SECRET_KEY="test",
    ALLOWED_HOSTS=["testserver"],
    CACHES={"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache", "LOCATION": "cache-test"}},
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
from django.utils.cache import patch_vary_headers

factory = RequestFactory()

def run_case(raw_header):
    cache.clear()
    calls = 0

    def view(request):
        nonlocal calls
        calls += 1
        response = HttpResponse("origin-" + str(calls))
        if raw_header:
            response["Set-Cookie"] = "example=value; Path=/; HttpOnly"
        else:
            response.set_cookie("example", "value", httponly=True)
        patch_vary_headers(response, ("Cookie",))
        return response

    middleware = CacheMiddleware(view, cache_timeout=60)
    first = middleware(factory.get("/case/"))
    second = middleware(factory.get("/case/"))
    return calls, first, second

normal_calls, _, _ = run_case(False)
raw_calls, raw_first, raw_second = run_case(True)

print("Django", django.get_version())
print("set_cookie origin calls:", normal_calls)
print("raw-header origin calls:", raw_calls)
print("raw first cookies:", dict(raw_first.cookies))
print("raw second header:", raw_second.get("Set-Cookie"))
print("raw second body:", raw_second.content.decode())

assert normal_calls == 2
assert not raw_first.cookies
assert raw_calls == 1
assert raw_second.get("Set-Cookie") == "example=value; Path=/; HttpOnly"
assert raw_second.content == raw_first.content

print("RESULT=REPRODUCED")
