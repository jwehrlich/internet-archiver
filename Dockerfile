from ruby:2.6.3
WORKDIR /app
CMD run.rb
RUN apt update && apt upgrade -yq && gem install bundler -v 2.4.22
RUN bundle config set force_ruby_platform true
COPY . /app
RUN bundle install
