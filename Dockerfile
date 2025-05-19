ARG RUBY_VERSION=3.4.1
FROM ruby:${RUBY_VERSION}-slim-bullseye as builder

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

RUN gem install bundler --version '~> 2.4' --no-document

COPY Gemfile Gemfile.lock ./
RUN bundle config set deployment 'true' \
	&& bundle config set without 'development test' \
	&& bundle install --jobs ${BUNDLE_JOBS} --retry 3

COPY . .

FROM ruby:${RUBY_VERSION}-slim-bullseye as final

LABEL maintainer="damacus"
LABEL description="CookstyleBot Ruby application"

ENV LANG C.UTF-8
ENV APP_HOME /usr/src/app
ENV APP_ENV production # Set default environment for the final image

RUN apt-get update -qq \
	&& apt-get install -y --no-install-recommends \
		git \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR ${APP_HOME}

COPY --from=builder /bundle /bundle
COPY --from=builder ${APP_HOME} ${APP_HOME}

RUN chmod +x ./bin/run_cookstyle_bot

ENTRYPOINT ["./bin/run_cookstyle_bot"]
