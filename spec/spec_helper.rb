require 'simplecov'
require 'simplecov-json'

# Start SimpleCov for code coverage tracking
SimpleCov.start do
  add_filter '/spec/'
  add_filter '/bin/'
  add_filter '/config/'
  
  # Output coverage reports
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::JSONFormatter
  ])
  
  # Track coverage for Lambda source code
  add_group 'Lambda Functions', 'src/lambda'
  add_group 'Utilities', 'src/lambda/util'
  
  # Minimum coverage threshold
  minimum_coverage 80
  minimum_coverage_by_file 70
end

require 'json'
require 'aws-sdk-sns'
require 'aws-sdk-sqs'

# Load application code
require_relative '../src/lambda/util/logger'
require_relative '../src/lambda/util/emf'
require_relative '../src/lambda/util/sqs-worker'

# RSpec configuration
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  # Use expect syntax
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Suppress output during tests (puts statements)
  config.before(:each) do
    allow($stdout).to receive(:puts)
  end

  # Configure AWS SDK stubs
  config.before(:each) do
    Aws.config[:stub_responses] = true
  end

  config.after(:each) do
    Aws.config[:stub_responses] = false
  end
end
