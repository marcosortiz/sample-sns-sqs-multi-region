require 'spec_helper'

RSpec.describe EmfLogger do
  let(:namespace) { 'TestNamespace' }
  let(:service_name) { 'TestService' }
  let(:emf_logger) { EmfLogger.new(namespace, service_name) }

  describe '#initialize' do
    it 'creates a new EmfLogger instance' do
      expect(emf_logger).to be_a(EmfLogger)
    end

    it 'sets the namespace' do
      expect(emf_logger.instance_variable_get(:@namespace)).to eq(namespace)
    end

    it 'sets the service name' do
      expect(emf_logger.instance_variable_get(:@service_name)).to eq(service_name)
    end
  end

  describe '#log_metrics' do
    let(:report) do
      {
        batch_size: 10,
        success_count: 9,
        failed_count: 1,
        retries: 2,
        duration: 1.5,
        process_rate: 6.0,
        producer_to_sns_latency: 100,
        sns_to_sqs_latency: 50,
        sqs_to_lambda_lacency: 25,
        lambda_to_code_latency: 15,
        latency: 200
      }
    end

    it 'logs metrics in EMF format' do
      expect { emf_logger.log_metrics(report) }.not_to raise_error
    end

    it 'outputs valid JSON' do
      output = nil
      allow($stdout).to receive(:puts) do |arg|
        output = arg
      end

      emf_logger.log_metrics(report)
      
      expect { JSON.parse(output) }.not_to raise_error
      parsed_output = JSON.parse(output)
      
      expect(parsed_output).to be_a(Hash)
    end

    it 'includes _aws metadata' do
      output = nil
      allow($stdout).to receive(:puts) do |arg|
        output = arg
      end

      emf_logger.log_metrics(report)
      parsed_output = JSON.parse(output)
      
      expect(parsed_output['_aws']).to be_a(Hash)
      expect(parsed_output['_aws']['CloudWatchMetrics']).to be_an(Array)
      expect(parsed_output['_aws']['Timestamp']).to be_a(Integer)
    end

    it 'includes correct namespace in CloudWatch metrics' do
      output = nil
      allow($stdout).to receive(:puts) do |arg|
        output = arg
      end

      emf_logger.log_metrics(report)
      parsed_output = JSON.parse(output)
      
      expect(parsed_output['_aws']['CloudWatchMetrics'][0]['Namespace']).to eq(namespace)
    end

    it 'includes service name dimension' do
      output = nil
      allow($stdout).to receive(:puts) do |arg|
        output = arg
      end

      emf_logger.log_metrics(report)
      parsed_output = JSON.parse(output)
      
      expect(parsed_output['ServiceName']).to eq(service_name)
      expect(parsed_output['_aws']['CloudWatchMetrics'][0]['Dimensions']).to include(['ServiceName'])
    end

    it 'includes all metrics from the report' do
      output = nil
      allow($stdout).to receive(:puts) do |arg|
        output = arg
      end

      emf_logger.log_metrics(report)
      parsed_output = JSON.parse(output)
      
      expect(parsed_output['BatchSize']).to eq(10)
      expect(parsed_output['SuccessCount']).to eq(9)
      expect(parsed_output['FailedCount']).to eq(1)
      expect(parsed_output['Retries']).to eq(2)
      expect(parsed_output['Duration']).to eq(1.5)
      expect(parsed_output['ProcessingRate']).to eq(6.0)
    end

    it 'includes latency metrics from the report' do
      output = nil
      allow($stdout).to receive(:puts) do |arg|
        output = arg
      end

      emf_logger.log_metrics(report)
      parsed_output = JSON.parse(output)
      
      expect(parsed_output['ProducerToSnsLatency']).to eq(100)
      expect(parsed_output['SnsToSqsLatency']).to eq(50)
      expect(parsed_output['SqsToLambdaLatency']).to eq(25)
      expect(parsed_output['LambdaToCodeLatency']).to eq(15)
      expect(parsed_output['Latency']).to eq(200)
    end

    it 'creates proper metric definitions with units' do
      output = nil
      allow($stdout).to receive(:puts) do |arg|
        output = arg
      end

      emf_logger.log_metrics(report)
      parsed_output = JSON.parse(output)
      
      metrics = parsed_output['_aws']['CloudWatchMetrics'][0]['Metrics']
      expect(metrics).to be_an(Array)
      expect(metrics.length).to eq(report.keys.length)
      
      # Check a few specific metrics
      batch_size_metric = metrics.find { |m| m['Name'] == 'BatchSize' }
      expect(batch_size_metric['Unit']).to eq('Count')
      
      duration_metric = metrics.find { |m| m['Name'] == 'Duration' }
      expect(duration_metric['Unit']).to eq('Seconds')
      
      latency_metric = metrics.find { |m| m['Name'] == 'Latency' }
      expect(latency_metric['Unit']).to eq('Milliseconds')
    end

    context 'when report has minimal data' do
      let(:minimal_report) do
        {
          batch_size: 5,
          success_count: 5,
          failed_count: 0
        }
      end

      it 'logs metrics without errors' do
        expect { emf_logger.log_metrics(minimal_report) }.not_to raise_error
      end

      it 'includes only provided metrics' do
        output = nil
        allow($stdout).to receive(:puts) do |arg|
          output = arg
        end

        emf_logger.log_metrics(minimal_report)
        parsed_output = JSON.parse(output)
        
        expect(parsed_output['BatchSize']).to eq(5)
        expect(parsed_output['SuccessCount']).to eq(5)
        expect(parsed_output['FailedCount']).to eq(0)
      end
    end

    context 'when report is empty' do
      let(:empty_report) { {} }

      it 'logs without errors' do
        expect { emf_logger.log_metrics(empty_report) }.not_to raise_error
      end

      it 'produces valid EMF structure with no metrics' do
        output = nil
        allow($stdout).to receive(:puts) do |arg|
          output = arg
        end

        emf_logger.log_metrics(empty_report)
        parsed_output = JSON.parse(output)
        
        expect(parsed_output['_aws']).to be_a(Hash)
        expect(parsed_output['_aws']['CloudWatchMetrics'][0]['Metrics']).to eq([])
      end
    end
  end

  describe 'METRICS_HASH constant' do
    it 'contains all expected metric definitions' do
      expect(EmfLogger::METRICS_HASH).to be_a(Hash)
      expect(EmfLogger::METRICS_HASH.keys).to include(
        :batch_size,
        :success_count,
        :failed_count,
        :retries,
        :duration,
        :process_rate,
        :producer_to_sns_latency,
        :producer_to_sqs_latency,
        :sns_to_sqs_latency,
        :sqs_to_lambda_lacency,
        :lambda_to_code_latency,
        :latency
      )
    end

    it 'has proper structure for each metric' do
      EmfLogger::METRICS_HASH.each do |key, value|
        expect(value).to be_a(Hash)
        expect(value).to have_key(:name)
        expect(value).to have_key(:unit)
        expect(value[:name]).to be_a(String)
        expect(value[:unit]).to be_a(String)
      end
    end
  end
end
