import asyncio
import gzip

from django.conf import settings

settings.configure(
    SECRET_KEY="local-asgi-security-test",
    DEBUG=False,
    ALLOWED_HOSTS=["testserver"],
    ROOT_URLCONF=__name__,
    MIDDLEWARE=[
        "django.middleware.security.SecurityMiddleware",
        "django.middleware.gzip.GZipMiddleware",
        "django.middleware.http.ConditionalGetMiddleware",
        "django.middleware.clickjacking.XFrameOptionsMiddleware",
        "django.middleware.csp.ContentSecurityPolicyMiddleware",
    ],
    SECURE_HSTS_SECONDS=3600,
    SECURE_HSTS_INCLUDE_SUBDOMAINS=True,
    SECURE_HSTS_PRELOAD=True,
    SECURE_CONTENT_TYPE_NOSNIFF=True,
    SECURE_REFERRER_POLICY="same-origin",
    SECURE_CROSS_ORIGIN_OPENER_POLICY="same-origin",
    SECURE_CSP={"default-src": ["'self'"]},
    SECURE_CSP_REPORT_ONLY={},
    X_FRAME_OPTIONS="DENY",
    USE_TZ=False,
)

import django
django.setup()

from django.http import HttpResponse, StreamingHttpResponse
from django.test import AsyncClient
from django.urls import path


async def normal(request):
    await asyncio.sleep(0)
    return HttpResponse(("normal-" + "A" * 4000).encode(), content_type="text/plain")


async def stream(request):
    async def gen():
        for _ in range(4):
            await asyncio.sleep(0)
            yield b"B" * 1024
    return StreamingHttpResponse(gen(), content_type="text/plain")


urlpatterns = [
    path("normal/", normal),
    path("stream/", stream),
]


def assert_security_headers(response):
    assert response["Strict-Transport-Security"] == "max-age=3600; includeSubDomains; preload"
    assert response["X-Content-Type-Options"] == "nosniff"
    assert response["Referrer-Policy"] == "same-origin"
    assert response["Cross-Origin-Opener-Policy"] == "same-origin"
    assert response["X-Frame-Options"] == "DENY"
    assert "default-src 'self'" in response["Content-Security-Policy"]


async def read_stream(response):
    chunks=[]
    async for chunk in response.streaming_content:
        chunks.append(chunk)
    return b"".join(chunks)


async def main():
    client = AsyncClient()

    normal_response = await client.get(
        "/normal/",
        secure=True,
        headers={"accept-encoding": "gzip"},
    )
    print("normal status:", normal_response.status_code)
    print("normal headers:", dict(normal_response.items()))
    assert normal_response.status_code == 200
    assert_security_headers(normal_response)
    assert normal_response["Content-Encoding"] == "gzip"
    assert "Accept-Encoding" in normal_response["Vary"]
    assert normal_response["ETag"].startswith('W/"')
    normal_body = gzip.decompress(normal_response.content)
    assert normal_body.startswith(b"normal-")

    streaming_response = await client.get(
        "/stream/",
        secure=True,
        headers={"accept-encoding": "gzip"},
    )
    print("stream status:", streaming_response.status_code)
    print("stream headers:", dict(streaming_response.items()))
    assert streaming_response.status_code == 200
    assert_security_headers(streaming_response)
    assert streaming_response["Content-Encoding"] == "gzip"
    assert "Accept-Encoding" in streaming_response["Vary"]
    compressed = await read_stream(streaming_response)
    body = gzip.decompress(compressed)
    assert body == b"B" * 4096

    # Conditional GET must still work through the regrouped synchronous
    # middleware chain around an async view.
    etag = normal_response["ETag"]
    conditional = await client.get(
        "/normal/",
        secure=True,
        headers={"if-none-match": etag, "accept-encoding": "gzip"},
    )
    print("conditional status:", conditional.status_code)
    print("conditional headers:", dict(conditional.items()))
    assert conditional.status_code == 304
    assert_security_headers(conditional)

    print("Django", django.get_version())
    print("RESULT=SECURITY_HEADERS_INTACT")


asyncio.run(main())
