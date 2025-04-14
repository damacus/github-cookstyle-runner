FROM ruby:3.2-slim

LABEL maintainer="Damacus"
LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.name="github-cookstyle-runner"
LABEL org.label-schema.description="A cookstyle runner system for Github Repositories"
LABEL org.label-schema.url="https://github.com/damacus/github-cookstyle-runner"
LABEL org.label-schema.vcs-url="https://github.com/damacus/github-cookstyle-runner"

# Install dependencies: git for cloning, curl/jq for GitHub API, build-essential for gems
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    jq \
    build-essential \
 && rm -rf /var/lib/apt/lists/*

# Copy Gemfile and install gems
COPY Gemfile* /usr/src/app/
WORKDIR /usr/src/app
RUN bundle install --jobs $(nproc) --retry 3

COPY app /app

ENTRYPOINT ["/app/entrypoint.sh"]
