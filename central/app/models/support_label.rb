# Catálogo global da equipe; nomes continuam no contrato existente com as contas.
class SupportLabel < ActiveRecord::Base
  before_validation { self.name = name.to_s.strip }
  validates :name, presence: true, length: {maximum:40}, uniqueness: {case_sensitive:false}, format: {without: /,/}
  validates :color, format: {with: /\A#[0-9a-fA-F]{6}\z/}
  validates :description, length: {maximum:160}
  def text_color
    r,g,b=color.delete_prefix('#').scan(/../).map{|part|part.to_i(16)}
    (r*0.299+g*0.587+b*0.114)>153 ? '#0f172a' : '#ffffff'
  end
end
