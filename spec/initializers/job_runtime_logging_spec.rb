# frozen_string_literal: true

require "rails_helper"

class JobRuntimeLoggingSpecJob < ApplicationJob
  queue_as :default

  def perform(*); end
end

RSpec.describe JobRuntimeLogging do
  it "resume argumentos sem expor valores de strings" do
    job = JobRuntimeLoggingSpecJob.new("token-secreto", { email: "admin@example.com", page: 2 }, [1, 2, 3])

    details = described_class.job_details(job, include_arguments: true)

    expect(details).to include("class=JobRuntimeLoggingSpecJob")
    expect(details).to include("args=[String(13b), Hash(keys=email,page), Array(size=3)]")
    expect(details).not_to include("token-secreto")
    expect(details).not_to include("admin@example.com")
  end
end
