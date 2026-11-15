# Native 4K video download site
Vercel hosts the static UI. Render hosts the Python FastAPI streaming service running yt-dlp + FFmpeg. The backend is deliberately locked to the single linked video (Q8RQ7D5MzW8) to avoid an open video conversion proxy.
## Endpoints
GET /api/health: liveness
GET /api/info: returns exact native stream heights
GET /api/download?height=2160: remuxes original video+audio on the fly to a fragmented MP4 without upscaling or buffering full files to disk.
If YouTube blocks datacenter access, this endpoint returns an error. A resolution is shown only after a successful format inspection. A valid 2160p stream is not guaranteed.
