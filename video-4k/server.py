import os
import re
import time
import threading
import subprocess
from urllib.parse import urlparse, parse_qs
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from yt_dlp import YoutubeDL
import imageio_ffmpeg

VIDEO_ID = "Q8RQ7D5MzW8"
VIDEO_URL = f"https://www.youtube.com/watch?v={VIDEO_ID}"
APP_NAME = "Native4K Streamer"
app = FastAPI(title=APP_NAME)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["GET"], allow_headers=["*"])
_cache = {"timestamp": 0, "video": None}
_cache_lock = threading.Lock()
_stream_slots = threading.BoundedSemaphore(2)

def extract_video():
    with _cache_lock:
        if _cache["video"] and time.time() - _cache["timestamp"] < 300:
            return _cache["video"]
        options = {
            "quiet": True, "no_warnings": True, "noplaylist": True,
            "skip_download": True, "socket_timeout": 25,
            "extractor_args": {"youtube": {"player_client": ["web", "android"]}},
        }
        try:
            with YoutubeDL(options) as ydl:
                video = ydl.extract_info(VIDEO_URL, download=False)
        except Exception as e:
            raise HTTPException(status_code=503, detail="YouTube stream lookup failed. YouTube may be blocking server-hosted downloads: " + str(e)[:200])
        if not video or video.get("id") != VIDEO_ID:
            raise HTTPException(status_code=502, detail="Video identity verification failed.")
        _cache.update(timestamp=time.time(), video=video)
        return video

def playable_formats(info):
    fmts = info.get("formats") or []
    videos = [f for f in fmts if f.get("vcodec") not in (None, "none") and f.get("height") and str(f.get("url","")).startswith("https://") and f.get("protocol") in ("https", "http")]
    audios = [f for f in fmts if f.get("acodec") not in (None, "none") and f.get("vcodec") == "none" and str(f.get("url","")).startswith("https://") and f.get("protocol") in ("https", "http")]
    return videos, audios

def allowed_source(f):
    host = urlparse(f["url"]).hostname or ""
    return host.endswith(".googlevideo.com") or host == "googlevideo.com"

@app.get("/api/health")
def health():
    return {"ok": True, "service": APP_NAME, "streaming": True}

@app.get("/api/info")
def info():
    v = extract_video()
    videos, audios = playable_formats(v)
    available = sorted(set(int(f["height"]) for f in videos))
    return {
        "id": VIDEO_ID,
        "title": v.get("title") or "Your video",
        "channel": v.get("uploader") or "YouTube",
        "duration": v.get("duration"),
        "thumbnail": v.get("thumbnail") or f"https://i.ytimg.com/vi/{VIDEO_ID}/maxresdefault.jpg",
        "resolutions": available,
        "hasAudio": bool(audios),
        "native4k": 2160 in available,
        "message": None if available else "No accessible direct video formats were returned by YouTube.",
    }

@app.get("/api/download")
def download(height: int = 2160):
    if height not in (144, 240, 360, 480, 720, 1080, 1440, 2160, 2880, 4320):
        raise HTTPException(status_code=400, detail="Invalid resolution.")
    if not _stream_slots.acquire(blocking=False):
        raise HTTPException(status_code=429, detail="Two downloads are already running. Please retry.")
    try:
        v = extract_video()
        videos, audios = playable_formats(v)
        eligible = [f for f in videos if int(f["height"]) == height and allowed_source(f)]
        if not eligible:
            raise HTTPException(status_code=404, detail=f"Native {height}p is unavailable for this video. Check available resolutions.")
        if not audios:
            raise HTTPException(status_code=502, detail="Separate audio stream unavailable; cannot produce a video with audio.")
        video = max(eligible, key=lambda f: (float(f.get("fps") or 0), float(f.get("tbr") or 0), f.get("ext") == "mp4"))
        valid_audio = [f for f in audios if allowed_source(f)]
        if not valid_audio:
            raise HTTPException(status_code=502, detail="Accessible audio source unavailable.")
        audio = max(valid_audio, key=lambda f: (f.get("acodec","").startswith("mp4a"), float(f.get("abr") or f.get("tbr") or 0)))
        def header_args(f):
            headers = f.get("http_headers") or {}
            safe = [(k, str(value).replace("\r","").replace("\n","")) for k,value in headers.items() if re.match(r"^[A-Za-z0-9-]+$",k)]
            return ["-headers", "".join(f"{k}: {value}\r\n" for k,value in safe)] if safe else []
        cmd = [
            imageio_ffmpeg.get_ffmpeg_exe(), "-hide_banner", "-loglevel", "error", "-nostdin",
            *header_args(video), "-i", video["url"],
            *header_args(audio), "-i", audio["url"],
            "-map", "0:v:0", "-map", "1:a:0",
            "-c:v", "copy", "-c:a", "copy",
            "-movflags", "frag_keyframe+empty_moov+default_base_moof",
            "-f", "mp4", "pipe:1"
        ]
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
        def stream():
            try:
                while True:
                    chunk = proc.stdout.read(128 * 1024)
                    if not chunk:
                        break
                    yield chunk
            finally:
                try:
                    if proc.poll() is None:
                        proc.terminate()
                        proc.wait(timeout=3)
                except Exception:
                    proc.kill()
                if proc.stdout:
                    proc.stdout.close()
                _stream_slots.release()
        filename = f"M4rkim-PROTAGONISTAS-{height}p.mp4"
        return StreamingResponse(stream(), media_type="video/mp4", headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
            "X-Accel-Buffering": "no"
        })
    except BaseException:
        _stream_slots.release()
        raise
