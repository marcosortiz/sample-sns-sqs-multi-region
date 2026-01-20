require 'spec_helper'

RSpec.describe SqsWorker do
  let(:worker) { SqsWorker.new }
  
  let(:sqs_record) do
    {
      'messageId' => 'msg-001',
      'body' => '{"message":"Test message","recorded_at":1640000000000}',
      'attributes' => {
        'SentTimestamp' => '1640000010000',
        'ApproximateFirstReceiveTimestamp' => '1640000015000'
      }
    }
  end

  let(:sns_sqs_record) do
    {
      'messageId' => 'msg-002',
      'body' => '{"Type":"Notification","MessageId":"sns-msg-001","TopicArn":"arn:aws:sns:us-east-1:123456789012:test-topic","Message":"{\"message\":\"SNS message\",\"recorded_at\":1640000000000}","Timestamp":"2021-12-20T12:00:10.000Z"}',
      'attributes' => {
        'SentTimestamp' => '1640000015000',
        'ApproximateFirstReceiveTimestamp' => '1640000020000'
      }
    }
  end

  describe '#batch_process_records' do
    context 'with successful processing' do
      it 'processes a single record successfully' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 0, 1)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key(:report)
        expect(result).to have_key(:failed_records)
      end

      it 'returns correct batch size' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 0, 1)
        
        expect(result[:report][:batch_size]).to eq(1)
      end

      it 'returns correct success count' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 0, 1)
        
        expect(result[:report][:success_count]).to eq(1)
        expect(result[:report][:failed_count]).to eq(0)
      end

      it 'processes multiple records' do
        records = [sqs_record, sqs_record.dup, sqs_record.dup]
        result = worker.batch_process_records(records, 0, 2)
        
        expect(result[:report][:batch_size]).to eq(3)
        expect(result[:report][:success_count]).to eq(3)
      end

      it 'returns empty failed_records array' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 0, 1)
        
        expect(result[:failed_records]).to be_empty
      end
    end

    context 'with failed processing' do
      before do
        # Mock process_record to fail
        allow_any_instance_of(SqsWorker).to receive(:process_record).and_return(false)
      end

      it 'tracks failed records' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 0, 1)
        
        expect(result[:report][:failed_count]).to eq(1)
        expect(result[:report][:success_count]).to eq(0)
        expect(result[:failed_records].length).to eq(1)
      end

      it 'includes failed record in failed_records array' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 0, 1)
        
        expect(result[:failed_records]).to include(sqs_record)
      end
    end

    context 'with retry logic' do
      let(:call_count) { [] }

      before do
        # Mock process_record to fail first time, succeed on retry
        allow_any_instance_of(SqsWorker).to receive(:process_record) do
          call_count << 1
          call_count.length > 1
        end
      end

      it 'retries failed records' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 2, 1)
        
        expect(call_count.length).to be > 1
      end

      it 'reports correct retry count on success' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 2, 1)
        
        expect(result[:report][:retries]).to be >= 0
      end

      it 'eventually succeeds after retries' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 3, 1)
        
        expect(result[:report][:success_count]).to eq(1)
        expect(result[:failed_records]).to be_empty
      end
    end

    context 'with max_retries exhausted' do
      before do
        allow_any_instance_of(SqsWorker).to receive(:process_record).and_return(false)
      end

      it 'stops after max_retries' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 2, 1)
        
        expect(result[:report][:failed_count]).to eq(1)
        expect(result[:failed_records].length).to eq(1)
      end
    end

    context 'report metrics' do
      it 'includes duration' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 0, 1)
        
        expect(result[:report][:duration]).to be_a(Numeric)
        expect(result[:report][:duration]).to be >= 0
      end

      it 'includes process_rate' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 0, 1)
        
        expect(result[:report][:process_rate]).to be_a(Numeric)
        expect(result[:report][:process_rate]).to be > 0
      end

      it 'includes latency metrics' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 0, 1)
        
        expect(result[:report][:sqs_to_lambda_lacency]).to be_a(Numeric)
        expect(result[:report][:lambda_to_code_latency]).to be_a(Numeric)
        expect(result[:report][:latency]).to be_a(Numeric)
      end

      it 'includes producer_to_sqs_latency for direct SQS messages' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 0, 1)
        
        expect(result[:report][:producer_to_sqs_latency]).to be_a(Numeric)
      end

      it 'includes SNS latencies for SNS-originated messages' do
        records = [sns_sqs_record]
        result = worker.batch_process_records(records, 0, 1)
        
        expect(result[:report][:producer_to_sns_latency]).to be_a(Numeric)
        expect(result[:report][:sns_to_sqs_latency]).to be_a(Numeric)
      end

      it 'does not include SNS latencies for direct SQS messages' do
        records = [sqs_record]
        result = worker.batch_process_records(records, 0, 1)
        
        expect(result[:report]).not_to have_key(:producer_to_sns_latency)
        expect(result[:report]).not_to have_key(:sns_to_sqs_latency)
      end
    end

    context 'with thread_count parameter' do
      it 'processes records with specified thread count' do
        records = [sqs_record] * 10
        result = worker.batch_process_records(records, 0, 5)
        
        expect(result[:report][:batch_size]).to eq(10)
        expect(result[:report][:success_count]).to eq(10)
      end

      it 'handles thread_count larger than record count' do
        records = [sqs_record, sqs_record.dup]
        result = worker.batch_process_records(records, 0, 10)
        
        expect(result[:report][:batch_size]).to eq(2)
        expect(result[:report][:success_count]).to eq(2)
      end
    end
  end

  describe '#is_sns_originated (private)' do
    it 'identifies SNS-originated messages' do
      parsed_body = {
        'Type' => 'Notification',
        'TopicArn' => 'arn:aws:sns:us-east-1:123456789012:test-topic',
        'Message' => '{"test":"data"}'
      }
      
      result = worker.send(:is_sns_originated, parsed_body)
      expect(result).to be true
    end

    it 'identifies direct SQS messages' do
      parsed_body = {
        'message' => 'Direct SQS message',
        'recorded_at' => 1640000000000
      }
      
      result = worker.send(:is_sns_originated, parsed_body)
      expect(result).to be false
    end

    it 'returns false when Type is not Notification' do
      parsed_body = {
        'Type' => 'Other',
        'TopicArn' => 'arn:aws:sns:us-east-1:123456789012:test-topic'
      }
      
      result = worker.send(:is_sns_originated, parsed_body)
      expect(result).to be false
    end

    it 'returns false when TopicArn is missing' do
      parsed_body = {
        'Type' => 'Notification'
      }
      
      result = worker.send(:is_sns_originated, parsed_body)
      expect(result).to be false
    end
  end

  describe '#parse_message (private)' do
    it 'returns message as-is for direct SQS messages' do
      parsed_body = {
        'message' => 'Test message',
        'recorded_at' => 1640000000000
      }
      
      result = worker.send(:parse_message, parsed_body, false)
      expect(result).to eq(parsed_body)
    end

    it 'extracts and parses Message field for SNS messages' do
      parsed_body = {
        'Type' => 'Notification',
        'Message' => '{"message":"SNS message","data":"test"}'
      }
      
      result = worker.send(:parse_message, parsed_body, true)
      expect(result).to be_a(Hash)
      expect(result['message']).to eq('SNS message')
      expect(result['data']).to eq('test')
    end

    it 'handles nested JSON in SNS Message field' do
      nested_message = { 'key' => 'value', 'nested' => { 'data' => 123 } }
      parsed_body = {
        'Type' => 'Notification',
        'Message' => nested_message.to_json
      }
      
      result = worker.send(:parse_message, parsed_body, true)
      expect(result['key']).to eq('value')
      expect(result['nested']['data']).to eq(123)
    end
  end

  describe '#calculate_latencies (private)' do
    let(:current_time) { 1640000020000 }
    
    context 'for direct SQS messages' do
      let(:message) { { 'recorded_at' => 1640000000000 } }
      let(:body) { {} }
      
      it 'calculates producer_to_sqs_latency' do
        latencies = worker.send(:calculate_latencies, sqs_record, body, message, false, current_time)
        
        expect(latencies[:producer_to_sqs_latency]).to be_a(Numeric)
        expect(latencies[:producer_to_sqs_latency]).to eq(15000) # 1640000015000 - 1640000000000
      end

      it 'calculates sqs_to_lambda_lacency' do
        latencies = worker.send(:calculate_latencies, sqs_record, body, message, false, current_time)
        
        expect(latencies[:sqs_to_lambda_lacency]).to be_a(Numeric)
        expect(latencies[:sqs_to_lambda_lacency]).to eq(5000) # 1640000015000 - 1640000010000
      end

      it 'calculates lambda_to_code_latency' do
        latencies = worker.send(:calculate_latencies, sqs_record, body, message, false, current_time)
        
        expect(latencies[:lambda_to_code_latency]).to be_a(Numeric)
        expect(latencies[:lambda_to_code_latency]).to eq(5000) # current_time - 1640000015000
      end

      it 'calculates total latency' do
        latencies = worker.send(:calculate_latencies, sqs_record, body, message, false, current_time)
        
        expect(latencies[:latency]).to be_a(Numeric)
        expect(latencies[:latency]).to eq(20000) # current_time - recorded_at
      end

      it 'does not include SNS-specific latencies' do
        latencies = worker.send(:calculate_latencies, sqs_record, body, message, false, current_time)
        
        expect(latencies).not_to have_key(:producer_to_sns_latency)
        expect(latencies).not_to have_key(:sns_to_sqs_latency)
      end
    end

    context 'for SNS-originated messages' do
      let(:message) { { 'recorded_at' => 1640000000000 } }
      let(:body) do
        {
          'Timestamp' => '2021-12-20T12:00:10.000Z',
          'Type' => 'Notification'
        }
      end
      
      it 'calculates producer_to_sns_latency' do
        latencies = worker.send(:calculate_latencies, sns_sqs_record, body, message, true, current_time)
        
        expect(latencies[:producer_to_sns_latency]).to be_a(Numeric)
      end

      it 'calculates sns_to_sqs_latency' do
        latencies = worker.send(:calculate_latencies, sns_sqs_record, body, message, true, current_time)
        
        expect(latencies[:sns_to_sqs_latency]).to be_a(Numeric)
      end

      it 'calculates all other latencies' do
        latencies = worker.send(:calculate_latencies, sns_sqs_record, body, message, true, current_time)
        
        expect(latencies[:sqs_to_lambda_lacency]).to be_a(Numeric)
        expect(latencies[:lambda_to_code_latency]).to be_a(Numeric)
        expect(latencies[:latency]).to be_a(Numeric)
      end

      it 'does not include producer_to_sqs_latency' do
        latencies = worker.send(:calculate_latencies, sns_sqs_record, body, message, true, current_time)
        
        expect(latencies).not_to have_key(:producer_to_sqs_latency)
      end
    end
  end

  describe '#process_record (private)' do
    it 'returns true for successful processing' do
      message = { 'message' => 'Test' }
      result = worker.send(:process_record, message)
      
      expect(result).to be true
    end

    it 'handles hash messages' do
      message = { 'key' => 'value', 'data' => [1, 2, 3] }
      result = worker.send(:process_record, message)
      
      expect(result).to be true
    end

    it 'handles string messages' do
      message = 'Simple string message'
      result = worker.send(:process_record, message)
      
      expect(result).to be true
    end

    context 'when processing fails' do
      it 'returns false on error' do
        # Mock puts to raise an error
        allow($stdout).to receive(:puts).and_raise(StandardError.new('Processing error'))
        
        message = { 'message' => 'Test' }
        result = worker.send(:process_record, message)
        
        expect(result).to be false
      end

      it 'catches StandardError' do
        allow($stdout).to receive(:puts).and_raise(StandardError.new('Test error'))
        
        message = { 'message' => 'Test' }
        expect { worker.send(:process_record, message) }.not_to raise_error
      end
    end
  end

  describe 'thread safety' do
    it 'processes records safely across multiple threads' do
      records = (1..20).map do |i|
        {
          'messageId' => "msg-#{i}",
          'body' => "{\"message\":\"Message #{i}\",\"recorded_at\":1640000000000}",
          'attributes' => {
            'SentTimestamp' => '1640000010000',
            'ApproximateFirstReceiveTimestamp' => '1640000015000'
          }
        }
      end
      
      result = worker.batch_process_records(records, 0, 5)
      
      expect(result[:report][:batch_size]).to eq(20)
      expect(result[:report][:success_count]).to eq(20)
      expect(result[:failed_records]).to be_empty
    end

    it 'tracks failures correctly across threads' do
      records = (1..10).map do |i|
        {
          'messageId' => "msg-#{i}",
          'body' => "{\"message\":\"Message #{i}\",\"recorded_at\":1640000000000}",
          'attributes' => {
            'SentTimestamp' => '1640000010000',
            'ApproximateFirstReceiveTimestamp' => '1640000015000'
          }
        }
      end
      
      # Fail processing for some records
      call_count = 0
      allow_any_instance_of(SqsWorker).to receive(:process_record) do
        call_count += 1
        call_count.odd? # Fail odd numbered calls
      end
      
      result = worker.batch_process_records(records, 0, 3)
      
      expect(result[:report][:success_count] + result[:report][:failed_count]).to eq(10)
    end
  end
end
