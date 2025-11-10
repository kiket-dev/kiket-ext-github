FROM ruby:3.4-slim

WORKDIR /app

# Install dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git && \
    rm -rf /var/lib/apt/lists/*

# Copy Gemfile
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy application code
COPY . .

# Expose port
EXPOSE 9393

# Start server
CMD ["bundle", "exec", "puma", "-C", "puma.rb"]
