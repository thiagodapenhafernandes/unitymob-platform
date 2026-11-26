class ChavesNaMaoLeadProcessingJob < ApplicationJob
  self.log_arguments = false
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(receipt_id)
    receipt = ChavesNaMaoLeadReceipt.find_by(id: receipt_id)
    return unless receipt

    receipt.with_lock { ChavesNaMao::ReceiveLead.call(receipt) }
  end
end
