ARG RUBY_VERSION=3.4.1
FROM ruby:${RUBY_VERSION}-slim-bullseye AS builder

LABEL maintainer="damacus"
LABEL description="CookstyleBot Ruby application"

ENV LANG C.UTF-8
ENV APP_HOME /usr/src/app
ENV BUNDLE_PATH /bundle
ENV BUNDLE_WITHOUT "development:test"
ENV BUNDLE_JOBS $(nproc)

RUN apt-get update -qq \
	&& apt-get install -y --no-install-recommends \
		build-essential \
		git \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR ${APP_HOME}

RUN gem install bundler --no-document

COPY Gemfile Gemfile.lock ./

# Configure bundler without using deployment mode (which sets frozen)
RUN bundle config set --local without 'development:test' \
	&& bundle install --jobs 4 --retry 3

COPY . .

FROM ruby:${RUBY_VERSION}-slim-bullseye AS final

LABEL maintainer="damacus"
LABEL description="CookstyleBot Ruby application"

ENV LANG C.UTF-8
ENV APP_HOME /usr/src/app
ENV APP_ENV production

RUN apt-get update -qq \
	&& apt-get install -y --no-install-recommends \
		git \
	&& rm -rf /var/lib/apt/lists/* \
	&& groupadd -r cookstyle \
	&& useradd -r -g cookstyle -d ${APP_HOME} -s /bin/bash -c "Cookstyle user" cookstyle

WORKDIR ${APP_HOME}

COPY --chown=cookstyle:cookstyle --from=builder /bundle /bundle
COPY --chown=cookstyle:cookstyle --from=builder ${APP_HOME} ${APP_HOME}

RUN chmod +x ./bin/run_cookstyle_bot

USER cookstyle

ENTRYPOINT ["./bin/run_cookstyle_bot"]
