require 'spec_helper'

# Load the handler
require_relative '../../src/lambda/sqs-consumer'

RSpec.describe 'Lambda Handler' do
  let(:context) do
    double(
      'context',
      invoked_function_arn: 'arn:aws:lambda:us-east-1:123456789012:function:test',
      function_name: 'test-function',
      memory_limit_in_mb: 512,
      request_id: 'test-request-id',
      log_group_name: '/aws/lambda/test-function',
      log_stream_name: '2021/12/20/[$LATEST]test',
      deadline_ms: Time.now.to_i * 1000 + 30000
    )
  end

  let(:sqs_event) do
    JSON.parse(File.read('spec/fixtures/sqs_event.json'))
  end

  let(:sns_sqs_event) do
    JSON.parse(File.read('spec/fixtures/sns_sqs_event.json'))
  end

  let(:batch_sqs_event) do
    JSON.parse(File.read('spec/fixtures/batch_sqs_event.json'))
  end

  describe '#handler' do
    context 'with single SQS record' do
      it 'processes the event successfully' do
        result = handler(event: sqs_event, context: context)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key('batchItemFailures')
      end

      it 'returns empty batchItemFailures on success' do
        result = handler(event: sqs_event, context: context)
        
        expect(result['batchItemFailures']).to be_an(Array)
        expect(result['batchItemFailures']).to be_empty
      end

      it 'does not raise errors' do
        expect { handler(event: sqs_event, context: context) }.not_to raise_error
      end
    end

    context 'with SNS-originated SQS record' do
      it 'processes SNS message successfully' do
        result = handler(event: sns_sqs_event, context: context)
        
        expect(result).to be_a(Hash)
        expect(result['batchItemFailures']).to be_empty
      end

      it 'handles SNS message format' do
        expect { handler(event: sns_sqs_event, context: context) }.not_to raise_error
      end
    end

    context 'with multiple records' do
      it 'processes batch of records' do
        result = handler(event: batch_sqs_event, context: context)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key('batchItemFailures')
      end

      it 'returns empty failures for successful batch' do
        result = handler(event: batch_sqs_event, context: context)
        
        expect(result['batchItemFailures']).to be_empty
      end
    end

    context 'with failed records' do
      before do
        # Mock the worker to return failed records
        allow_any_instance_of(SqsWorker).to receive(:batch_process_records).and_return(
          {
            report: {
              batch_size: 1,
              success_count: 0,
              failed_count: 1,
              retries: 0,
              duration: 0.1,
              process_rate: 0,
              sqs_to_lambda_lacency: 100,
              lambda_to_code_latency: 50,
              latency: 150
            },
            failed_records: [sqs_event['Records'][0]]
          }
        )
      end

      it 'returns failed record messageIds' do
        result = handler(event: sqs_event, context: context)
        
        expect(result['batchItemFailures']).not_to be_empty
        expect(result['batchItemFailures'].length).to eq(1)
      end

      it 'includes itemIdentifier for failed records' do
        result = handler(event: sqs_event, context: context)
        
        failure = result['batchItemFailures'][0]
        expect(failure).to have_key('itemIdentifier')
        expect(failure['itemIdentifier']).to eq('msg-001')
      end

      it 'returns proper batch failure response format' do
        result = handler(event: sqs_event, context: context)
        
        expect(result).to be_a(Hash)
        expect(result['batchItemFailures']).to be_an(Array)
        result['batchItemFailures'].each do |failure|
          expect(failure).to have_key('itemIdentifier')
          expect(failure['itemIdentifier']).to be_a(String)
        end
      end
    end

    context 'with partial failures' do
      let(:multi_record_event) do
        {
          'Records' => [
            sqs_event['Records'][0],
            sqs_event['Records'][0].dup.merge('messageId' => 'msg-002'),
            sqs_event['Records'][0].dup.merge('messageId' => 'msg-003')
          ]
        }
      end

      before do
        # Mock to fail one record
        allow_any_instance_of(SqsWorker).to receive(:batch_process_records).and_return(
          {
            report: {
              batch_size: 3,
              success_count: 2,
              failed_count: 1,
              retries: 0,
              duration: 0.1,
              process_rate: 20,
              sqs_to_lambda_lacency: 100,
              lambda_to_code_latency: 50,
              latency: 150
            },
            failed_records: [multi_record_event['Records'][1]]
          }
        )
      end

      it 'returns only failed record IDs' do
        result = handler(event: multi_record_event, context: context)
        
        expect(result['batchItemFailures'].length).to eq(1)
        expect(result['batchItemFailures'][0]['itemIdentifier']).to eq('msg-002')
      end
    end

    context 'input validation' do
      it 'handles empty Records array' do
        empty_event = { 'Records' => [] }
        
        expect { handler(event: empty_event, context: context) }.not_to raise_error
      end

      it 'processes event with Records key' do
        expect(sqs_event).to have_key('Records')
        result = handler(event: sqs_event, context: context)
        
        expect(result).to be_a(Hash)
      end
    end

    context 'integration with SqsWorker' do
      it 'calls batch_process_records with correct parameters' do
        worker_double = instance_double(SqsWorker)
        allow(SqsWorker).to receive(:new).and_return(worker_double)
        
        expect(worker_double).to receive(:batch_process_records).with(
          sqs_event['Records'],
          3,
          5
        ).and_return(
          {
            report: {
              batch_size: 1,
              success_count: 1,
              failed_count: 0,
              retries: 0,
              duration: 0.1,
              process_rate: 10,
              sqs_to_lambda_lacency: 100,
              lambda_to_code_latency: 50,
              latency: 150
            },
            failed_records: []
          }
        )
        
        # Redefine WORKER constant temporarily
        stub_const('WORKER', worker_double)
        
        handler(event: sqs_event, context: context)
      end
    end

    context 'integration with EmfLogger' do
      it 'calls log_metrics with report data' do
        emf_double = instance_double(EmfLogger)
        allow(EmfLogger).to receive(:new).and_return(emf_double)
        
        # Stub the worker to return a specific report
        allow_any_instance_of(SqsWorker).to receive(:batch_process_records).and_return(
          {
            report: {
              batch_size: 1,
              success_count: 1,
              failed_count: 0,
              retries: 0,
              duration: 0.1,
              process_rate: 10,
              sqs_to_lambda_lacency: 100,
              lambda_to_code_latency: 50,
              latency: 150
            },
            failed_records: []
          }
        )
        
        expect(emf_double).to receive(:log_metrics).with(
          hash_including(
            batch_size: 1,
            success_count: 1,
            failed_count: 0
          )
        )
        
        # Redefine EMF constant temporarily
        stub_const('EMF', emf_double)
        
        handler(event: sqs_event, context: context)
      end
    end

    context 'response format' do
      it 'returns response in AWS Lambda SQS batch response format' do
        result = handler(event: sqs_event, context: context)
        
        expect(result).to be_a(Hash)
        expect(result.keys).to eq(['batchItemFailures'])
      end

      it 'returns batchItemFailures as array' do
        result = handler(event: sqs_event, context: context)
        
        expect(result['batchItemFailures']).to be_an(Array)
      end

      it 'each failure contains itemIdentifier' do
        # Mock to return failures
        allow_any_instance_of(SqsWorker).to receive(:batch_process_records).and_return(
          {
            report: { batch_size: 1, success_count: 0, failed_count: 1 },
            failed_records: [{ 'messageId' => 'test-id' }]
          }
        )
        
        result = handler(event: sqs_event, context: context)
        
        result['batchItemFailures'].each do |failure|
          expect(failure.keys).to eq(['itemIdentifier'])
        end
      end
    end

    context 'error handling' do
      it 'handles worker errors gracefully' do
        allow_any_instance_of(SqsWorker).to receive(:batch_process_records).and_raise(StandardError.new('Worker error'))
        
        expect { handler(event: sqs_event, context: context) }.to raise_error(StandardError, 'Worker error')
      end

      it 'handles logger errors gracefully' do
        allow_any_instance_of(EmfLogger).to receive(:log_metrics).and_raise(StandardError.new('Logger error'))
        
        expect { handler(event: sqs_event, context: context) }.to raise_error(StandardError, 'Logger error')
      end
    end
  end

  describe 'Lambda constants' do
    it 'initializes WORKER constant' do
      expect(defined?(WORKER)).to eq('constant')
      expect(WORKER).to be_a(SqsWorker)
    end

    it 'initializes EMF constant' do
      expect(defined?(EMF)).to eq('constant')
      expect(EMF).to be_a(EmfLogger)
    end

    it 'EMF has correct namespace and service name' do
      expect(EMF.instance_variable_get(:@namespace)).to eq('SnsSqsMultiRegion')
      expect(EMF.instance_variable_get(:@service_name)).to eq('SqsConsumer')
    end
  end

  describe 'Lambda handler signature' do
    it 'accepts event and context keyword arguments' do
      expect(method(:handler).parameters).to eq([[:keyreq, :event], [:keyreq, :context]])
    end

    it 'requires both event and context' do
      expect { handler }.to raise_error(ArgumentError)
      expect { handler(event: sqs_event) }.to raise_error(ArgumentError)
      expect { handler(context: context) }.to raise_error(ArgumentError)
    end
  end
end
