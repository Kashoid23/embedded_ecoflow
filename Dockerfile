# syntax=docker/dockerfile:1

# ---- build: install gems (needs compilers, which the final image doesn't) ----
FROM ruby:3.4-slim AS build

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV BUNDLE_WITHOUT=test \
    BUNDLE_PATH=/usr/local/bundle

COPY Gemfile Gemfile.lock* ./
RUN bundle install --jobs 4 \
 && rm -rf /usr/local/bundle/cache

# ---- runtime ----
FROM ruby:3.4-slim

# tzdata: day boundaries and the outage schedule are in Kyiv time
RUN apt-get update \
 && apt-get install -y --no-install-recommends tzdata \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 1000 app

WORKDIR /app
ENV BUNDLE_WITHOUT=test \
    BUNDLE_PATH=/usr/local/bundle \
    APP_ENV=production \
    TZ=Europe/Kyiv \
    BIND=0.0.0.0 \
    PORT=10000 \
    DATA_DIR=/var/data

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=app:app . .

# No secrets in the image: they come from the environment at runtime
# (Render environment variables, or `docker run --env-file .env`). See .dockerignore.

EXPOSE 10000
ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/server"]
