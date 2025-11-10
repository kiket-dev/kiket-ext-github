# frozen_string_literal: true

ENV["RACK_ENV"] = "test"

require "rspec"
require "rack/test"
require "webmock/rspec"
require "vcr"

require_relative "../app"

RSpec.configure do |config|
  config.include Rack::Test::Methods

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed

  # Reset state between tests
  config.before(:each) do
    GitHubExtension.settings.repositories.clear
    GitHubExtension.settings.pull_requests.clear
    GitHubExtension.settings.issue_mappings.clear
    GitHubExtension.settings.webhook_deliveries.clear
    GitHubExtension.settings.sync_jobs.clear
  end
end

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
end

def app
  GitHubExtension
end
