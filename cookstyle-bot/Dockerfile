FROM ruby:3.4-slim

LABEL maintainer="Dan Webb <dan.webb@damacus.io>"
LABEL org.opencontainers.image.source="https://github.com/damacus/github-cookstyle-runner"
LABEL org.opencontainers.image.description="A Ruby application to automatically run cookstyle against repos found by GitHub topics"

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Set up working directory
WORKDIR /app

# Copy Gemfile and install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

# Copy application code
COPY . .

# Set environment variables
ENV APP_ENV=production

# Run as non-root user for security
RUN groupadd -r cookstyle && useradd -r -g cookstyle cookstyle
RUN chown -R cookstyle:cookstyle /app
USER cookstyle

# Command to run the application
CMD ["bundle", "exec", "ruby", "bin/cookstyle-bot"]
