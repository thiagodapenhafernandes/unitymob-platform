require 'spec_helper'
require 'rake'

RSpec.describe 'Imovelweb support tasks' do
  before(:all) { load File.expand_path('../Rakefile', __dir__) unless Rake::Task.task_defined?('imovelweb:configure_callbacks') }
  around do |example|
    keys = %w[ENVIRONMENT CALLBACK_URL APPLY CLIENT_CODE REFERENCE EXTERNAL_ID IMOVELWEB_SANDBOX_CALLBACK_TOKEN]
    saved = ENV.to_h.slice(*keys)
    keys.each { |key| ENV.delete(key) }
    example.run
  ensure
    keys.each { |key| saved.key?(key) ? ENV[key] = saved[key] : ENV.delete(key) }
    %w[configure_callbacks associate_listing].each { |name| Rake::Task["imovelweb:#{name}"].reenable }
  end

  it 'does not call the portal when preparing callback configuration in dry-run' do
    ENV['CALLBACK_URL'] = 'https://gateway.example.com/webhooks/imovelweb/sandbox'
    expect(Gateway::ImovelwebClient).not_to receive(:new)
    expect { Rake::Task['imovelweb:configure_callbacks'].invoke }.to output(/apply=false/).to_stdout
  end

  it 'applies and verifies the callback only when explicitly requested' do
    url = 'https://gateway.example.com/webhooks/imovelweb/sandbox'
    ENV['CALLBACK_URL'] = url
    ENV['IMOVELWEB_SANDBOX_CALLBACK_TOKEN'] = 't' * 32
    ENV['APPLY'] = 'true'
    client = instance_double(Gateway::ImovelwebClient)
    expect(Gateway::ImovelwebClient).to receive(:new).with(environment: 'sandbox').and_return(client)
    expect(client).to receive(:configure_callbacks).with(url: url, token: 't' * 32)
    expect(client).to receive(:callbacks).and_return({'url' => url})
    expect { Rake::Task['imovelweb:configure_callbacks'].invoke }.to output(/callback_confirmed=true/).to_stdout
  end

  it 'does not associate a listing remotely without APPLY' do
    ENV['CLIENT_CODE'] = 'client'
    ENV['REFERENCE'] = 'AP-1'
    ENV['EXTERNAL_ID'] = '123'
    expect(Gateway::ImovelwebClient).not_to receive(:new)
    expect { Rake::Task['imovelweb:associate_listing'].invoke }.to output(/apply=false/).to_stdout
  end
end
