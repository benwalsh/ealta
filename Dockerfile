# The cloud image — the SAME app the Pi runs, built for a container host
# (RAILS_ENV=cloud, an RDS/managed DB via the pure-Ruby trilogy adapter). The Pi
# never uses this; it runs bare-metal from the repo (see deploy/).
#
# It boots on stations/example (baked in). To deploy as a specific station, get that
# station's profile into the image — stage it into the build context, or FROM this image
# and COPY it — and set STATION_PROFILE to its path (see a station overlay's deploy
# workflow, which bakes its own profile into the image, for one way).
#
# Multi-stage: the build stage compiles gems + runs the Vite build (React SPA +
# Stimulus bundle) + precompiles assets; the runtime stage is a slim Puma server.
#
# Build from the REPO ROOT — the app needs dashboard/ and model/. It ships NO bird art:
# illustrations live in a station profile and are served from there at runtime, so stage
# your profile into the image (see the station-overlay deploy workflow) and set
# STATION_PROFILE to its path:
#     docker build -t ealta .
ARG RUBY_VERSION=4.0.5

FROM ruby:${RUBY_VERSION}-slim-bookworm AS build

# Native-gem toolchain (sqlite3 is still a base dependency; trilogy is pure Ruby)
# + git/curl, and bun to run the Vite build.
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      build-essential git curl unzip libsqlite3-dev libssl-dev libyaml-dev pkg-config \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}" \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_WITH="cloud"

WORKDIR /app/dashboard

# Gems first — cached until the lockfile changes.
COPY dashboard/Gemfile dashboard/Gemfile.lock dashboard/.ruby-version ./
RUN bundle install --jobs 4 --retry 3 && rm -rf ~/.bundle

# JS deps next — cached until package.json / bun.lock change.
COPY dashboard/package.json dashboard/bun.lock ./
RUN bun install --frozen-lockfile

# The rest of the repo (app + illustrations + model data), then build assets.
# Precompile in production env (SQLite, no external DB) — the digested output is
# identical to cloud, and it avoids any DB connection during the image build.
WORKDIR /app
COPY . .
WORKDIR /app/dashboard
RUN SECRET_KEY_BASE_DUMMY=1 RAILS_ENV=production bin/rails assets:precompile

# --- Runtime -----------------------------------------------------------------
FROM ruby:${RUBY_VERSION}-slim-bookworm

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends libsqlite3-0 libyaml-0-2 curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --shell /bin/bash app

ENV RAILS_ENV=cloud \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_WITH="cloud" \
    RAILS_LOG_TO_STDOUT=1 \
    PORT=3000

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=app:app /app /app

USER app
WORKDIR /app/dashboard
EXPOSE 3000
# App Runner health check hits /up; keep one here too for local `docker run`.
HEALTHCHECK --interval=30s --timeout=4s --start-period=25s \
  CMD curl -fsS http://localhost:3000/up || exit 1
# The entrypoint runs db:prepare before the server boots (RDS is private — this is
# the only place migrations can run; it's idempotent and single-instance-safe).
ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
