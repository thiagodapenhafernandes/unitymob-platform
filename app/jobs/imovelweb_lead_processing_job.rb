class ImovelwebLeadProcessingJob < ApplicationJob
  self.log_arguments = false
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(receipt_id)
    receipt = ImovelwebLeadReceipt.find_by(id: receipt_id)
    return unless receipt
    receipt.with_lock { Imovelweb::ReceiveLead.call(receipt) }
  end
end
