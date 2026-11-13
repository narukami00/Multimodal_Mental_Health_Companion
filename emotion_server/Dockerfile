FROM python:3.11-slim

ARG INSTALL_MODE=ci

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    EMOTION_MOCK=1 \
    EMOTION_FACE=0 \
    PORT=8766

WORKDIR /app

COPY requirements-ci.txt requirements.txt ./
RUN if [ "$INSTALL_MODE" = "full" ]; then \
      pip install --no-cache-dir -r requirements.txt; \
    else \
      pip install --no-cache-dir -r requirements-ci.txt; \
    fi

COPY emotion_api.py cue.py pipeline_utils.py heads.py face_runtime.py runtime_config.py emotion_engine.py check_assets.py artifact_manifest.json ./

RUN groupadd --system solace && useradd --system --gid solace --create-home solace \
    && chown -R solace:solace /app
USER solace

EXPOSE 8766

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8766/healthz', timeout=2)" || exit 1

CMD ["sh", "-c", "uvicorn emotion_api:app --host 0.0.0.0 --port ${PORT:-8766}"]
