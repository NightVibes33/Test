FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg nodejs ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY video-4k/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY video-4k/server.py ./server.py
ENV PYTHONUNBUFFERED=1
CMD ["sh","-c","uvicorn server:app --host 0.0.0.0 --port ${PORT:-10000}"]
