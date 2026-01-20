# Quick Start Guide - Testing

## Setup (One Time)

```bash
# Install Ruby dependencies
bundle install
```

## Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/lambda/sqs_consumer_spec.rb

# Run with specific format
bundle exec rspec --format documentation
```

## View Coverage

```bash
# After running tests, open coverage report
open coverage/index.html
# or on Linux: xdg-open coverage/index.html
```

## SAM Local Testing

```bash
# Build the Lambda function
sam build

# Test with sample SQS event
sam local invoke SqsConsumer -e spec/fixtures/sqs_event.json

# Test with SNS-originated event
sam local invoke SqsConsumer -e spec/fixtures/sns_sqs_event.json

# Test with batch of messages
sam local invoke SqsConsumer -e spec/fixtures/batch_sqs_event.json

# Debug mode
sam local invoke SqsConsumer -e spec/fixtures/sqs_event.json --debug
```

## Test Files

- **spec/lambda/sqs_consumer_spec.rb** - Main Lambda handler tests
- **spec/lambda/util/sqs_worker_spec.rb** - SqsWorker class tests (batch processing, retry logic, latency)
- **spec/lambda/util/emf_logger_spec.rb** - EmfLogger class tests (CloudWatch metrics)

## Test Fixtures

- **spec/fixtures/sqs_event.json** - Direct SQS message
- **spec/fixtures/sns_sqs_event.json** - SNS-originated message
- **spec/fixtures/batch_sqs_event.json** - Multiple messages

## Coverage Requirements

- Overall: 80% minimum
- Per-file: 70% minimum

## For More Details

See **TEST_README.md** for comprehensive testing guide including:
- Prerequisites and installation
- Detailed test descriptions
- Writing new tests
- CI/CD integration
- Troubleshooting
