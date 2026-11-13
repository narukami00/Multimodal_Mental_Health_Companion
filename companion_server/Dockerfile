FROM python:3.11-slim

ARG INSTALL_MODE=ci

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    SOLACE_LLM_BACKEND=mock \
    SOLACE_STT=mock \
    SOLACE_TTS=mock \
    SOLACE_EMOTION=1 \
    SOLACE_EMOTION_URL=http://emotion:8766 \
    PORT=8000

WORKDIR /app

COPY requirements-ci.txt requirements.txt ./
RUN if [ "$INSTALL_MODE" = "full" ]; then \
      pip install --no-cache-dir -r requirements.txt; \
    else \
      pip install --no-cache-dir -r requirements-ci.txt; \
    fi

COPY . .

RUN groupadd --system solace && useradd --system --gid solace --create-home solace \
    && chown -R solace:solace /app
USER solace

EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2)" || exit 1

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
