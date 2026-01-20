# Testing Guide for SNS-SQS Multi-Region Lambda Functions

This guide provides comprehensive instructions for testing the Lambda functions in this repository, including unit tests, SAM local testing, and best practices.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Running Unit Tests](#running-unit-tests)
- [Test Coverage](#test-coverage)
- [SAM Local Testing](#sam-local-testing)
- [Test Structure](#test-structure)
- [Writing New Tests](#writing-new-tests)
- [CI/CD Integration](#cicd-integration)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Software

1. **Ruby 3.3** - Matches the Lambda runtime
   ```bash
   ruby --version  # Should show ruby 3.3.x
   ```

2. **Bundler** - For managing Ruby dependencies
   ```bash
   gem install bundler
   ```

3. **AWS SAM CLI** - For local Lambda testing
   ```bash
   # Install SAM CLI
   # macOS
   brew tap aws/tap
   brew install aws-sam-cli
   
   # Linux
   # Follow: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html
   
   # Verify installation
   sam --version
   ```

4. **Docker** - Required for SAM local invoke
   ```bash
   docker --version
   ```

### Installing Dependencies

Install all Ruby dependencies including test frameworks:

```bash
bundle install
```

This will install:
- `rspec` - Testing framework
- `simplecov` - Code coverage reporting
- `simplecov-json` - JSON format for coverage reports
- `aws-sdk-sns` - AWS SNS SDK
- `aws-sdk-sqs` - AWS SQS SDK

## Running Unit Tests

### Run All Tests

Execute the complete test suite:

```bash
bundle exec rspec
```

### Run Specific Test Files

Run tests for a specific component:

```bash
# Test the main Lambda handler
bundle exec rspec spec/lambda/sqs_consumer_spec.rb

# Test the SqsWorker class
bundle exec rspec spec/lambda/util/sqs_worker_spec.rb

# Test the EmfLogger class
bundle exec rspec spec/lambda/util/emf_logger_spec.rb
```

### Run Specific Test Cases

Run a specific describe block or test case:

```bash
# Run tests matching a pattern
bundle exec rspec spec/lambda/sqs_consumer_spec.rb -e "handler"

# Run a specific line number
bundle exec rspec spec/lambda/sqs_consumer_spec.rb:10
```

### Test Output Formats

```bash
# Documentation format (detailed)
bundle exec rspec --format documentation

# Progress format (dots)
bundle exec rspec --format progress

# JSON format (for CI/CD)
bundle exec rspec --format json --out rspec_results.json
```

### Verbose Output

To see more detailed output during test execution:

```bash
# Show pending tests
bundle exec rspec --format documentation --dry-run

# Show all output (including puts statements)
bundle exec rspec --format documentation --backtrace
```

## Test Coverage

### Viewing Coverage Reports

After running tests, SimpleCov automatically generates coverage reports:

1. **HTML Report** - Open in browser for detailed analysis
   ```bash
   open coverage/index.html
   # or on Linux
   xdg-open coverage/index.html
   ```

2. **JSON Report** - For programmatic analysis
   ```bash
   cat coverage/coverage.json
   ```

3. **Console Summary** - Displayed after test run
   ```
   Coverage report generated for RSpec
   XX.XX% covered at X.XX hits/line
   ```

### Coverage Thresholds

The project has minimum coverage requirements:
- **Overall Coverage**: 80%
- **Per-File Coverage**: 70%

Tests will fail if coverage drops below these thresholds.

### Understanding Coverage

- **Green**: Line is covered by tests
- **Red**: Line is not covered by tests
- **Yellow**: Line is partially covered

Focus on covering:
- Error handling paths
- Edge cases
- Different input variations
- Retry logic
- Thread safety

## SAM Local Testing

SAM CLI allows you to test Lambda functions locally before deployment.

### Build the Application

Build the Lambda function package:

```bash
sam build
```

This command:
- Packages the Lambda function code
- Resolves dependencies
- Prepares for local testing or deployment

### Invoke Lambda Locally

#### Using Event Files

Test with a single SQS message:

```bash
sam local invoke SqsConsumer -e spec/fixtures/sqs_event.json
```

Test with SNS-originated message:

```bash
sam local invoke SqsConsumer -e spec/fixtures/sns_sqs_event.json
```

Test with batch of messages:

```bash
sam local invoke SqsConsumer -e spec/fixtures/batch_sqs_event.json
```

#### Custom Event

Create a custom event and test:

```bash
# Create custom event
cat > custom_event.json << 'EOF'
{
  "Records": [
    {
      "messageId": "custom-001",
      "receiptHandle": "receipt-handle-custom",
      "body": "{\"message\":\"My custom message\",\"recorded_at\":1640000000000}",
      "attributes": {
        "ApproximateReceiveCount": "1",
        "SentTimestamp": "1640000010000",
        "SenderId": "AIDAIT2UOQQY3AUEKVGXU",
        "ApproximateFirstReceiveTimestamp": "1640000015000"
      },
      "messageAttributes": {},
      "md5OfBody": "098f6bcd4621d373cade4e832627b4f6",
      "eventSource": "aws:sqs",
      "eventSourceARN": "arn:aws:sqs:us-east-1:123456789012:test-queue",
      "awsRegion": "us-east-1"
    }
  ]
}
EOF

# Invoke with custom event
sam local invoke SqsConsumer -e custom_event.json
```

### Debug Mode

Run Lambda with debugging output:

```bash
sam local invoke SqsConsumer -e spec/fixtures/sqs_event.json --debug
```

### Environment Variables

Set environment variables for local testing:

```bash
sam local invoke SqsConsumer \
  -e spec/fixtures/sqs_event.json \
  --env-vars env.json
```

Example `env.json`:
```json
{
  "SqsConsumer": {
    "AWS_REGION": "us-east-1",
    "LOG_LEVEL": "DEBUG"
  }
}
```

### Start Local API Gateway

While this project uses SQS triggers, you can start a local API for testing:

```bash
sam local start-api
```

### Start Local Lambda Endpoint

Start a local endpoint for Lambda invocations:

```bash
sam local start-lambda
```

Then invoke using AWS CLI:

```bash
aws lambda invoke \
  --function-name SqsConsumer \
  --endpoint-url http://127.0.0.1:3001 \
  --payload file://spec/fixtures/sqs_event.json \
  response.json
```

## Test Structure

### Directory Layout

```
spec/
├── spec_helper.rb              # RSpec configuration and SimpleCov setup
├── fixtures/                   # Sample event payloads
│   ├── sqs_event.json         # Single direct SQS message
│   ├── sns_sqs_event.json     # SNS-originated message
│   └── batch_sqs_event.json   # Multiple messages
└── lambda/
    ├── sqs_consumer_spec.rb   # Main handler tests
    └── util/
        ├── sqs_worker_spec.rb # SqsWorker class tests
        └── emf_logger_spec.rb # EmfLogger class tests
```

### Test Components

#### 1. Main Handler Tests (`sqs_consumer_spec.rb`)

Tests the Lambda handler function including:
- Event processing
- Response format
- Integration with SqsWorker
- Integration with EmfLogger
- Error handling
- Partial batch failures

#### 2. SqsWorker Tests (`sqs_worker_spec.rb`)

Tests the worker class including:
- Batch processing
- Record processing
- Retry logic
- Message parsing (SQS vs SNS)
- Latency calculations
- Thread safety

#### 3. EmfLogger Tests (`emf_logger_spec.rb`)

Tests the logging class including:
- EMF format generation
- Metric logging
- CloudWatch Metrics structure
- JSON validation

### Test Fixtures

Located in `spec/fixtures/`, these JSON files simulate AWS SQS events:

- **sqs_event.json**: Direct SQS message
- **sns_sqs_event.json**: Message originated from SNS topic
- **batch_sqs_event.json**: Multiple messages for batch testing

## Writing New Tests

### RSpec Best Practices

1. **Use descriptive test names**
   ```ruby
   it 'processes SNS-originated messages correctly' do
     # test code
   end
   ```

2. **Follow the AAA pattern**
   ```ruby
   it 'calculates latency correctly' do
     # Arrange
     record = create_test_record
     
     # Act
     result = worker.calculate_latency(record)
     
     # Assert
     expect(result).to be > 0
   end
   ```

3. **Use contexts for different scenarios**
   ```ruby
   describe '#process_records' do
     context 'with valid records' do
       it 'processes successfully' do
         # test
       end
     end
     
     context 'with invalid records' do
       it 'handles errors gracefully' do
         # test
       end
     end
   end
   ```

4. **Mock AWS SDK calls**
   ```ruby
   before do
     Aws.config[:stub_responses] = true
   end
   ```

### Adding New Test Cases

1. Create a new spec file in the appropriate directory
2. Require `spec_helper`
3. Use `RSpec.describe` with the class or method name
4. Write tests using `it` blocks
5. Run tests to ensure they pass

Example:
```ruby
require 'spec_helper'

RSpec.describe MyNewClass do
  describe '#my_method' do
    it 'does something useful' do
      instance = MyNewClass.new
      result = instance.my_method
      
      expect(result).to eq(expected_value)
    end
  end
end
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Ruby
      uses: ruby/setup-ruby@v1
      with:
        ruby-version: 3.3
        bundler-cache: true
    
    - name: Run tests
      run: bundle exec rspec
    
    - name: Upload coverage
      uses: actions/upload-artifact@v3
      with:
        name: coverage
        path: coverage/
```

### Pre-deployment Checklist

Before deploying to AWS:

1. ✅ Run all unit tests
   ```bash
   bundle exec rspec
   ```

2. ✅ Check coverage meets thresholds (80%)
   ```bash
   open coverage/index.html
   ```

3. ✅ Test locally with SAM
   ```bash
   sam build
   sam local invoke SqsConsumer -e spec/fixtures/sqs_event.json
   ```

4. ✅ Validate SAM template
   ```bash
   sam validate
   ```

5. ✅ Review CloudWatch Logs locally
   - Check EMF log format
   - Verify metric dimensions
   - Confirm error handling

## Troubleshooting

### Common Issues

#### Tests Fail with "cannot load such file"

**Problem**: Ruby cannot find the required files.

**Solution**: Ensure you're running from the project root:
```bash
cd /path/to/sample-sns-sqs-multi-region
bundle exec rspec
```

#### Coverage Not Updating

**Problem**: SimpleCov not tracking changes.

**Solution**: Clean coverage data and re-run:
```bash
rm -rf coverage/
bundle exec rspec
```

#### SAM Build Fails

**Problem**: Dependencies not resolved.

**Solution**: Ensure Gemfile.lock is up to date:
```bash
bundle install
bundle lock
sam build
```

#### Docker Issues with SAM Local

**Problem**: SAM cannot connect to Docker.

**Solution**: Ensure Docker is running:
```bash
docker ps
# If error, start Docker daemon
```

#### Lambda Timeout in Local Testing

**Problem**: Function times out locally.

**Solution**: Increase timeout in template.yaml:
```yaml
Timeout: 60  # Increase from 30 to 60 seconds
```

#### Tests Pass Locally but Fail in CI

**Problem**: Environment differences.

**Solution**: 
- Check Ruby version matches
- Verify all dependencies in Gemfile
- Check for timezone issues
- Review CI logs for specific errors

### Debug Tests

Add debugging output to tests:

```ruby
it 'processes record' do
  record = create_record
  
  # Add debug output
  puts "Record: #{record.inspect}"
  
  result = worker.process(record)
  
  puts "Result: #{result.inspect}"
  
  expect(result).to be_truthy
end
```

Run with full output:

```bash
bundle exec rspec --format documentation --backtrace
```

### Performance Testing

Check test execution time:

```bash
bundle exec rspec --profile
```

This shows the 10 slowest tests, helping identify performance issues.

## Additional Resources

### AWS Documentation

- [AWS Lambda Ruby Runtime](https://docs.aws.amazon.com/lambda/latest/dg/lambda-ruby.html)
- [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html)
- [SQS Batch Processing](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)
- [Lambda Partial Batch Response](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html#services-sqs-batchfailurereporting)
- [EMF (Embedded Metric Format)](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format.html)

### Testing Resources

- [RSpec Documentation](https://rspec.info/documentation/)
- [SimpleCov Documentation](https://github.com/simplecov-ruby/simplecov)
- [AWS SDK for Ruby - Stubbing](https://docs.aws.amazon.com/sdk-for-ruby/v3/developer-guide/stubbing.html)
- [RSpec Best Practices](https://rspec.rubystyle.guide/)

### Repository Resources

- [Main README](README.md) - Project overview and deployment
- [template.yaml](template.yaml) - SAM template with Lambda configuration
- [Gemfile](Gemfile) - Ruby dependencies

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review test output and error messages
3. Check AWS SAM CLI logs with `--debug` flag
4. Review coverage reports for untested code paths

## Summary of Commands

```bash
# Install dependencies
bundle install

# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/lambda/sqs_consumer_spec.rb

# View coverage
open coverage/index.html

# Build for SAM
sam build

# Test locally with SAM
sam local invoke SqsConsumer -e spec/fixtures/sqs_event.json

# Validate SAM template
sam validate

# Deploy to AWS
sam deploy --guided
```

---

**Last Updated**: January 2026  
**Ruby Version**: 3.3  
**AWS SAM CLI Version**: 1.x+
