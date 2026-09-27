import asyncio
import os
import tempfile

DB_PATH = os.path.join(tempfile.gettempdir(), "django-asgi-isolation.sqlite3")
try:
    os.unlink(DB_PATH)
except FileNotFoundError:
    pass

from django.conf import settings

settings.configure(
    SECRET_KEY="local-asgi-isolation-test",
    DEBUG=False,
    ALLOWED_HOSTS=["testserver"],
    ROOT_URLCONF=__name__,
    INSTALLED_APPS=[
        "django.contrib.auth",
        "django.contrib.contenttypes",
        "django.contrib.sessions",
    ],
    MIDDLEWARE=[
        "django.contrib.sessions.middleware.SessionMiddleware",
        "django.middleware.csrf.CsrfViewMiddleware",
        "django.contrib.auth.middleware.AuthenticationMiddleware",
        "django.contrib.auth.middleware.RemoteUserMiddleware",
    ],
    DATABASES={
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": DB_PATH,
            "OPTIONS": {"timeout": 30},
        }
    },
    SESSION_ENGINE="django.contrib.sessions.backends.db",
    AUTHENTICATION_BACKENDS=["django.contrib.auth.backends.RemoteUserBackend"],
    PASSWORD_HASHERS=["django.contrib.auth.hashers.MD5PasswordHasher"],
    USE_TZ=False,
)

import django
django.setup()

from asgiref.sync import sync_to_async
from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.http import JsonResponse
from django.test import AsyncClient
from django.urls import path

call_command("migrate", verbosity=0, interactive=False)

User = get_user_model()
USERS = [f"user{i:02d}" for i in range(24)]
for username in USERS:
    User.objects.create_user(username=username)


async def whoami(request):
    # Force overlap around both auth/session reads.
    await asyncio.sleep(0.03)
    first = await request.auser()
    session_uid = await request.session.aget("_auth_user_id", None)
    await asyncio.sleep(0.03)
    second = await request.auser()
    return JsonResponse(
        {
            "first": first.get_username(),
            "second": second.get_username(),
            "session_uid": session_uid,
        }
    )


async def protected_post(request):
    return JsonResponse({"ok": True})


urlpatterns = [
    path("who/", whoami),
    path("protected/", protected_post),
]


async def one_identity(username):
    client = AsyncClient()
    response = await client.get("/who/", headers={"remote-user": username})
    assert response.status_code == 200, (username, response.status_code, response.content)
    data = response.json()
    assert data["first"] == username, (username, data)
    assert data["second"] == username, (username, data)
    expected_pk = await sync_to_async(
        lambda: str(User.objects.only("pk").get(username=username).pk),
        thread_sensitive=False,
    )()
    assert data["session_uid"] == expected_pk, (username, expected_pk, data)
    return username


async def main():
    # Start all identities at once. A middleware/context leak should manifest
    # as a response containing another request's username/session id.
    results = await asyncio.gather(*(one_identity(u) for u in USERS))
    assert results == USERS

    # Security control: CsrfViewMiddleware.process_view() must still execute
    # for an async unsafe-method view after middleware adaptation.
    csrf_client = AsyncClient(enforce_csrf_checks=True)
    csrf_response = await csrf_client.post("/protected/", data={"x": "1"})
    assert csrf_response.status_code == 403, csrf_response.status_code

    print("Django", django.get_version())
    print("concurrent identities:", len(results))
    print("unique identities:", len(set(results)))
    print("csrf missing-token status:", csrf_response.status_code)
    print("RESULT=ISOLATED")


asyncio.run(main())
