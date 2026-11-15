# Native4K Studio

A Vercel-first personal downloader for the linked YouTube video `Q8RQ7D5MzW8`. **This is source code, not a live deployment.** The Vercel connection returned HTTP 403 for project creation. 

## Deploy on Vercel
1. In [Vercel New Project](https://vercel.com/new), import `NightVibes33/Test`.
2. Choose branch `feature/native-4k-video-site` (set it as the production branch if you want the production URL to use it).
3. Set the project **Root Directory** to `video-4k`.
4. Deploy with the Python runtime enabled. `vercel.json` configures a 300-second maximum function duration.

## How it works
- `index.html`: responsive single-video UI, checks real available source heights and offers native 4K only if the stream exists.
- `api/index.py` and `server.py`: FastAPI, yt-dlp, imageio-ffmpeg. YouTube separate video/audio streams are remuxed into a fragmented MP4 by FFmpeg and returned as a streaming response. No deliberate upscaling or full-file buffering.
- `Dockerfile`: optional long-running deployment on a separate container host. Not required for the Vercel version.
- Endpoint `GET /api/health` for liveness and `GET /api/info` for availability.
- Endpoint `GET /api/download?height=2160` only succeeds when a 2160p source and a separate audio stream are accessible.

## Known limits
- YouTube may refuse playback/extraction from cloud data center IPs; this cannot be bypassed by UI code.
- An 11:51 4K download may exceed Vercel Hobby's 300-second function duration or streaming constraints.
- The project deliberately allows **only** this video ID to prevent an open download proxy and limit traffic costs.
- Do not claim 4K availability until `/api/info` confirms it. The actual live 4K download has not been end-to-end tested.
- Original codecs are copied without transcoding; codec/container combinations may be incompatible with some video players.

## Render one-service deployment

Use a Render **Docker Web Service**, not a static site. The Python server serves the homepage at `/`, video metadata at `/api/info`, streamed video downloads at `/api/download`, and health at `/api/health`.

- Git repository: `https://github.com/NightVibes33/Test`
- Branch: `feature/native-4k-video-site`
- Dockerfile: `video-4k/Dockerfile`
- Docker build context: repository root `.` (not `video-4k`)
- Listen address: `0.0.0.0`, port `PORT` (default `10000`)

A Render workspace can require a billing method before even free web-service creation. The current code is not evidence that downloading YouTube 4K streams will work from a cloud-hosted server. YouTube may deny access; output is streamed as a fragmented MP4.
