FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .
RUN SECRET_KEY=build-only DATABASE_URL=sqlite:///tmp/build.db python manage.py collectstatic --noinput

EXPOSE 8000
# Local (docker-compose sets DEV_SERVER=1): auto-reloading dev server.
# Hosted (Render etc.): migrate, load master data + admin login once, then the ASGI server on $PORT.
CMD ["sh", "-c", "python manage.py migrate --noinput && if [ \"$DEV_SERVER\" = 1 ]; then python manage.py runserver 0.0.0.0:8000; else python manage.py bootstrap && daphne -b 0.0.0.0 -p ${PORT:-8000} config.asgi:application; fi"]
