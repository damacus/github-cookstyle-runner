FROM ruby:3.4-slim@sha256:c1734f5d0a502ece7f35658c30168fe85777e21531d7c800386f1514f5207ac8

LABEL maintainer="Damacus <me@damacus.io>"
LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.name="github-cookstyle-runner"
LABEL org.label-schema.description="A cookstyle runner system for Github Repositories"
LABEL org.label-schema.url="https://github.com/damacus/github-cookstyle-runner"
LABEL org.label-schema.vcs-url="https://github.com/damacus/github-cookstyle-runner"

# Install base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    build-essential \
    ca-certificates \
    bash \
 && rm -rf /var/lib/apt/lists/*

# Set up working directory
WORKDIR /app

# Copy Gemfile and install dependencies
COPY Gemfile* ./
RUN bundle install --jobs $(nproc) --retry 3

# Copy application code (can be overridden by volume mount)
COPY bin /app/bin
COPY config /app/config
COPY lib /app/lib


# Default entrypoint for running the application
ENTRYPOINT ["/app/bin/cookstyle-runner"]
