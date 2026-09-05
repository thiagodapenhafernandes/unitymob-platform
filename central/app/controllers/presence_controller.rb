class PresenceController < ApplicationController
  def create
    current_staff_session.heartbeat!
    head :no_content
  end
end
