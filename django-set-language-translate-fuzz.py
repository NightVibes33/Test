import django
from django.conf import settings

settings.configure(
    SECRET_KEY="local-translate-fuzz",
    DEBUG=False,
    ALLOWED_HOSTS=["testserver"],
    ROOT_URLCONF=__name__,
    USE_I18N=True,
    LANGUAGE_CODE="en",
    LANGUAGES=[("en","English"),("nl","Dutch")],
    MIDDLEWARE=[],
)

django.setup()

from django.conf.urls.i18n import i18n_patterns
from django.http import HttpResponse
from django.test import Client
from django.urls import path
from django.utils.http import url_has_allowed_host_and_scheme
from django.views.i18n import set_language


def echo(request, value=""):
    return HttpResponse(value)


urlpatterns = [
    path("set-language/", set_language, name="set_language"),
]
urlpatterns += i18n_patterns(
    path("go/<path:value>/", echo, name="go"),
    path("<path:value>/", echo, name="catchall"),
)


CASES = [
    "/en/go/%2F%2Fevil.example/",
    "/en/go/%252F%252Fevil.example/",
    "/en/go/%5C%5Cevil.example/",
    "/en/go/%2f%5cevil.example/",
    "/en/go/http%3A%2F%2Fevil.example/",
    "/en/go/%40evil.example/",
    "/en/go/%23%2F%2Fevil.example/",
    "/en/go/%3F%2F%2Fevil.example/",
    "/en/%2F%2Fevil.example/",
    "/en/%252F%252Fevil.example/",
    "/en/%5C%5Cevil.example/",
    "/en/http%3A%2F%2Fevil.example/",
    "/en/%2e%2e/%2f%2fevil.example/",
    "/en/go/%E2%81%84%E2%81%84evil.example/",
]

client = Client()
unsafe = []

for next_url in CASES:
    accepted = url_has_allowed_host_and_scheme(
        next_url,
        allowed_hosts={"testserver"},
        require_https=False,
    )
    response = client.post(
        "/set-language/",
        {"next": next_url, "language": "nl"},
        HTTP_HOST="testserver",
    )
    location = response.get("Location")
    translated_safe = url_has_allowed_host_and_scheme(
        location,
        allowed_hosts={"testserver"},
        require_https=False,
    )
    print("CASE", repr(next_url))
    print(" accepted=", accepted)
    print(" status=", response.status_code)
    print(" location=", repr(location))
    print(" translated_safe=", translated_safe)
    print("---")
    if accepted and location and not translated_safe:
        unsafe.append((next_url, location))

print("Django", django.get_version())
print("UNSAFE_COUNT=", len(unsafe))
for src, dst in unsafe:
    print("UNSAFE", repr(src), "=>", repr(dst))

assert not unsafe, unsafe
print("RESULT=NO_OPEN_REDIRECT")
