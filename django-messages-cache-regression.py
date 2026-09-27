import http.client
import threading
from http.cookies import SimpleCookie

import django
from django.conf import settings

settings.configure(
    SECRET_KEY="local-test-secret",
    DEBUG=False,
    ALLOWED_HOSTS=["127.0.0.1", "localhost"],
    ROOT_URLCONF=__name__,
    INSTALLED_APPS=[
        "django.contrib.sessions",
        "django.contrib.messages",
    ],
    MIDDLEWARE=[
        "django.middleware.cache.UpdateCacheMiddleware",
        "django.contrib.sessions.middleware.SessionMiddleware",
        "django.contrib.messages.middleware.MessageMiddleware",
        "django.middleware.cache.FetchFromCacheMiddleware",
    ],
    SESSION_ENGINE="django.contrib.sessions.backends.signed_cookies",
    MESSAGE_STORAGE="django.contrib.messages.storage.fallback.FallbackStorage",
    CACHES={
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "messages-cache-isolation-test",
        }
    },
    CACHE_MIDDLEWARE_ALIAS="default",
    CACHE_MIDDLEWARE_SECONDS=60,
    CACHE_MIDDLEWARE_KEY_PREFIX="",
    USE_I18N=False,
    USE_TZ=False,
)
django.setup()

from django.contrib import messages
from django.http import HttpResponse
from django.urls import path
from django.core.wsgi import get_wsgi_application
from wsgiref.simple_server import make_server

hits = {"show": 0}


def set_message(request):
    if request.method != "POST":
        return HttpResponse(status=405)
    messages.info(request, "PRIVATE-FLASH-FOR-CLIENT-A")
    return HttpResponse("stored")


def show_message(request):
    hits["show"] += 1
    rendered = "|".join(str(message) for message in messages.get_messages(request))
    return HttpResponse(f"origin={hits['show']};messages={rendered}")


urlpatterns = [
    path("set/", set_message),
    path("show/", show_message),
]

application = get_wsgi_application()
server = make_server("127.0.0.1", 0, application)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
port = server.server_port


def request(method, path, headers=None):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    conn.request(method, path, headers=headers or {})
    response = conn.getresponse()
    body = response.read().decode()
    response_headers = response.getheaders()
    conn.close()
    return response.status, response_headers, body


def header_values(headers, name):
    return [value for key, value in headers if key.lower() == name.lower()]


try:
    set_status, set_headers, set_body = request("POST", "/set/")
    set_cookie_headers = header_values(set_headers, "Set-Cookie")
    cookie = SimpleCookie()
    for value in set_cookie_headers:
        cookie.load(value)
    message_cookie = cookie["messages"].value

    first = request(
        "GET",
        "/show/",
        headers={"Cookie": f"messages={message_cookie}"},
    )
    second = request("GET", "/show/")
finally:
    server.shutdown()
    thread.join(timeout=5)

print("Django", django.get_version())
print("set status/body:", set_status, set_body)
print("set Set-Cookie:", set_cookie_headers)
print("origin show hits:", hits["show"])
print("client A:", first)
print("client B:", second)

first_vary = header_values(first[1], "Vary")
second_vary = header_values(second[1], "Vary")
print("client A Vary:", first_vary)
print("client B Vary:", second_vary)

assert set_status == 200
assert "PRIVATE-FLASH-FOR-CLIENT-A" in first[2]
assert not first_vary, first_vary
assert hits["show"] == 1, "Second client should have been served from shared cache."
assert second[2] == first[2]
assert "PRIVATE-FLASH-FOR-CLIENT-A" in second[2]

print("RESULT=REPRODUCED")
