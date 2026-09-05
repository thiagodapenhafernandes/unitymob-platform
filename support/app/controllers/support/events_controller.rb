class Support::EventsController < ActionController::Base
  protect_from_forgery with: :null_session
  before_action :authenticate_account!
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from ActiveRecord::RecordInvalid, ArgumentError, KeyError, JSON::ParserError, with: -> { head :unprocessable_entity }
  rescue_from ActiveRecord::RecordNotUnique, Support::Exchange::Conflict, with: -> { head :conflict }

  def create
    payload = JSON.parse(request.raw_post)
    return head :unprocessable_entity unless payload.is_a?(Hash)
    return head :forbidden unless @account.active? || (!SupportDesk.central? && %w[account_state revoke_access].include?(payload["kind"]))
    Support::Exchange.receive(@account, payload)
    head :ok
  end

  private

  def authenticate_account!
    return head :payload_too_large if request.content_length.to_i > 72.megabytes
    @account = Support::Account.find_by(uid: request.headers["X-Support-Account"])
    timestamp = request.headers["X-Support-Timestamp"].to_s
    return head :unauthorized unless @account && timestamp.match?(/\A\d{10}\z/) && (Time.current.to_i - timestamp.to_i).abs <= 300
    expected = Support::Transport.signature(@account.secret, timestamp, request.raw_post)
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected, request.headers["X-Support-Signature"].to_s)
  end
end
