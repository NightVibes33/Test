import asyncio
import django
from django.conf import settings

settings.configure(
    SECRET_KEY="local-test",
    DEBUG=False,
    ALLOWED_HOSTS=["testserver"],
    ROOT_URLCONF=__name__,
    MIDDLEWARE=[
        "django.contrib.sessions.middleware.SessionMiddleware",
        "django.middleware.locale.LocaleMiddleware",
        "django.middleware.csp.ContentSecurityPolicyMiddleware",
    ],
    SESSION_ENGINE="django.contrib.sessions.backends.signed_cookies",
    SESSION_COOKIE_NAME="sessionid",
    LANGUAGE_CODE="en",
    LANGUAGES=[("en", "English"), ("fr", "French")],
    USE_I18N=True,
    USE_TZ=False,
    SECURE_CSP={},
    SECURE_CSP_REPORT_ONLY={},
)
django.setup()

from django.contrib.sessions.backends.signed_cookies import SessionStore
from django.http import HttpResponse
from django.middleware.csp import get_nonce
from django.test import AsyncClient
from django.urls import path
from django.utils import translation


async def state_view(request):
    # Force overlap between requests.
    await asyncio.sleep(0.002)
    identity = request.session.get("identity", "missing")
    request_lang = getattr(request, "LANGUAGE_CODE", "missing")
    active_lang = translation.get_language()
    nonce = str(get_nonce(request))
    await asyncio.sleep(0.002)
    return HttpResponse(f"{identity}|{request_lang}|{active_lang}|{nonce}")


urlpatterns = [path("state/", state_view)]


def make_cookie(identity):
    store = SessionStore()
    store["identity"] = identity
    store.save()
    return store.session_key


COOKIE_A = make_cookie("A")
COOKIE_B = make_cookie("B")


async def one_pair(i):
    a = AsyncClient()
    b = AsyncClient()
    a.cookies["sessionid"] = COOKIE_A
    b.cookies["sessionid"] = COOKIE_B

    ra, rb = await asyncio.gather(
        a.get("/state/", headers={"accept-language": "en"}),
        b.get("/state/", headers={"accept-language": "fr"}),
    )
    sa = ra.content.decode().split("|")
    sb = rb.content.decode().split("|")

    assert sa[0] == "A", (i, "A identity", sa, sb)
    assert sb[0] == "B", (i, "B identity", sa, sb)
    assert sa[1] == "en" and sa[2] == "en", (i, "A language", sa, sb)
    assert sb[1] == "fr" and sb[2] == "fr", (i, "B language", sa, sb)
    assert sa[3] and sb[3] and sa[3] != sb[3], (i, "nonce collision", sa, sb)
    return sa, sb


async def main():
    results = await asyncio.gather(*(one_pair(i) for i in range(50)))
    print("Django", django.get_version())
    print("pairs:", len(results))
    print("sample A:", results[0][0][:3], "nonce_len", len(results[0][0][3]))
    print("sample B:", results[0][1][:3], "nonce_len", len(results[0][1][3]))
    print("RESULT=ISOLATED")


asyncio.run(main())
