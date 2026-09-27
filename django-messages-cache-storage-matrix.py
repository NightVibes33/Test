import http.client
import os
import threading
from http.cookies import SimpleCookie

import django
from django.conf import settings

storage = os.environ["MESSAGE_STORAGE"]
expect_leak = os.environ["EXPECT_LEAK"] == "1"

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
    MESSAGE_STORAGE=storage,
    CACHES={
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "messages-cache-storage-matrix",
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
from django.core.wsgi import get_wsgi_application
from django.http import HttpResponse
from django.urls import path
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

def cookie_header_from(headers):
    jar = SimpleCookie()
    for value in header_values(headers, "Set-Cookie"):
        jar.load(value)
    return "; ".join(f"{key}={morsel.value}" for key, morsel in jar.items())

try:
    set_status, set_headers, set_body = request("POST", "/set/")
    cookie_header = cookie_header_from(set_headers)
    first = request("GET", "/show/", headers={"Cookie": cookie_header})
    second = request("GET", "/show/")
finally:
    server.shutdown()
    thread.join(timeout=5)

first_vary = header_values(first[1], "Vary")
second_vary = header_values(second[1], "Vary")

print("Django", django.get_version())
print("storage:", storage)
print("expect_leak:", expect_leak)
print("set Cookie header:", cookie_header)
print("origin show hits:", hits["show"])
print("client A body:", first[2])
print("client B body:", second[2])
print("client A Vary:", first_vary)
print("client B Vary:", second_vary)
print("client B Age:", header_values(second[1], "Age"))

assert set_status == 200
assert "PRIVATE-FLASH-FOR-CLIENT-A" in first[2]

if expect_leak:
    assert not any("cookie" in value.lower() for value in first_vary), first_vary
    assert hits["show"] == 1
    assert second[2] == first[2]
    assert "PRIVATE-FLASH-FOR-CLIENT-A" in second[2]
    print("RESULT=LEAK_REPRODUCED")
else:
    assert any("cookie" in value.lower() for value in first_vary), first_vary
    assert hits["show"] == 2
    assert "PRIVATE-FLASH-FOR-CLIENT-A" not in second[2]
    print("RESULT=CONTROL_ISOLATED")
