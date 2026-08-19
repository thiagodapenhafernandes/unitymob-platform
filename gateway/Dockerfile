FROM ruby:3.2.3-slim

ENV BUNDLE_DEPLOYMENT=true \
    BUNDLE_WITHOUT="development test" \
    RACK_ENV=production

RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends build-essential libpq-dev pkg-config \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

COPY . .

EXPOSE 4010

CMD ["bundle", "exec", "rackup", "--host", "127.0.0.1", "--port", "4010"]
