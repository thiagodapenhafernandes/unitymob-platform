class WhatsappTemplate < ApplicationRecord
  validates :name, presence: true

  scope :approved, -> { where(status: "APPROVED") }
  scope :ordered, -> { order(:name) }

  def approved? = status.to_s.upcase == "APPROVED"

  # Substitui {{1}}, {{2}}... pelos valores informados (preview / envio simples).
  def render_body(values = [])
    text = body.to_s
    Array(values).each_with_index do |val, i|
      text = text.gsub("{{#{i + 1}}}", val.to_s)
    end
    text
  end

  def variable_count
    body.to_s.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).max || 0
  end
end
