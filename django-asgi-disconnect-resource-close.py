import asyncio
import gc
import os

from django.conf import settings

settings.configure(
    SECRET_KEY="local-asgi-disconnect-test",
    DEBUG=False,
    ALLOWED_HOSTS=["testserver"],
    ROOT_URLCONF=__name__,
    MIDDLEWARE=[],
    USE_TZ=False,
)

import django
django.setup()

from django.core.asgi import get_asgi_application
from django.http import StreamingHttpResponse
from django.urls import path

state = {
    "opened": 0,
    "closed": 0,
    "fd": None,
}
first_body_sent = asyncio.Event()


async def body():
    fd = os.open(os.devnull, os.O_RDONLY)
    state["fd"] = fd
    state["opened"] += 1
    try:
        yield b"first-chunk"
        # The client disconnects while this generator is suspended.
        await asyncio.sleep(3600)
        yield b"never-reached"
    finally:
        os.close(fd)
        state["closed"] += 1


async def stream_view(request):
    return StreamingHttpResponse(body(), content_type="application/octet-stream")


urlpatterns = [
    path("stream/", stream_view),
]


async def main():
    app = get_asgi_application()
    receive_calls = 0
    sent = []

    async def receive():
        nonlocal receive_calls
        receive_calls += 1
        if receive_calls == 1:
            return {
                "type": "http.request",
                "body": b"",
                "more_body": False,
            }
        await first_body_sent.wait()
        return {"type": "http.disconnect"}

    async def send(message):
        sent.append(message)
        if (
            message["type"] == "http.response.body"
            and message.get("body")
        ):
            first_body_sent.set()

    scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "GET",
        "scheme": "http",
        "path": "/stream/",
        "raw_path": b"/stream/",
        "query_string": b"",
        "root_path": "",
        "headers": [(b"host", b"testserver")],
        "client": ("127.0.0.1", 12345),
        "server": ("testserver", 80),
    }

    await asyncio.wait_for(app(scope, receive, send), timeout=5)

    print("Django", django.get_version())
    print("opened:", state["opened"])
    print("closed immediately after handler:", state["closed"])
    print("response messages:", [m["type"] for m in sent])

    immediate = state["closed"]
    await asyncio.sleep(0)
    print("closed after one event-loop tick:", state["closed"])
    after_tick = state["closed"]

    gc.collect()
    await asyncio.sleep(0)
    print("closed after gc + one tick:", state["closed"])
    after_gc = state["closed"]

    assert state["opened"] == 1
    print("RESULT immediate=%d after_tick=%d after_gc=%d" % (
        immediate, after_tick, after_gc
    ))


asyncio.run(main())
