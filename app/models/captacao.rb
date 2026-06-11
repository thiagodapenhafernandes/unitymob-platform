# frozen_string_literal: true

# Captação de imóvel — intake preenchido pelo corretor em campo via wizard
# mobile-first. É um pipeline separado de Habitation (catálogo público);
# quando aprovada, admin promove manualmente.
class Captacao < ApplicationRecord
  self.table_name = "captacoes"

  belongs_to :corretor, class_name: "AdminUser"

  has_many_attached :fotos
  has_one_attached  :autorizacao_pdf

  enum property_kind: { residencial: 0, sala_comercial: 1, terreno: 2 }, _prefix: true
  enum modalidade:    { venda: 0, locacao_anual: 1, ambos: 2, locacao_diaria: 3 }, _prefix: true

  STEPS = %w[intro proprietario endereco caracteristicas infraestrutura negociacao visitas fotos review].freeze

  # Validações por step — só quando avança pra frente
  with_options on: :intro do
    validates :property_kind, :modalidade, presence: true
  end
  with_options on: :proprietario do
    validates :proprietario_nome, :proprietario_telefone, presence: true
  end
  with_options on: :endereco do
    validates :street, :street_number, :city, presence: true
  end
  with_options on: :caracteristicas do
    validates :area_privativa, presence: true, numericality: { greater_than: 0 }, unless: :property_kind_terreno?
    validates :area_total, presence: true, numericality: { greater_than: 0 }, if: :property_kind_terreno?
    validates :dormitorios, :banheiros, presence: true, if: :property_kind_residencial?
    validates :salas,       presence: true, if: :property_kind_sala_comercial?
  end
  with_options on: :negociacao do
    validates :valor_venda,   presence: true, numericality: { greater_than: 0 }, if: :requires_sale_price?
    validates :valor_locacao, presence: true, numericality: { greater_than: 0 }, if: :requires_rent_price?
  end

  scope :draft,          -> { where(completed: false) }
  scope :done,           -> { where(completed: true) }
  scope :by_period,      ->(start_date, end_date) { where(submitted_at: start_date..end_date) }
  scope :venda_type,     -> { where(modalidade: [:venda, :ambos]) }
  scope :locacao_type,   -> { where(modalidade: [:locacao_anual, :ambos, :locacao_diaria]) }

  def next_step
    STEPS[STEPS.index(step).to_i + 1]
  end

  def previous_step
    idx = STEPS.index(step).to_i
    idx.positive? ? STEPS[idx - 1] : nil
  end

  def progress_percentage
    ((STEPS.index(step).to_f / (STEPS.size - 1)) * 100).round
  end

  def requires_sale_price?
    modalidade_venda? || modalidade_ambos?
  end

  def requires_rent_price?
    modalidade_locacao_anual? || modalidade_ambos? || modalidade_locacao_diaria?
  end

  def skip_visitas?
    property_kind_terreno?
  end

  def display_title
    if property_kind_terreno?
      [edificio_nome.presence, street, street_number].compact_blank.join(" — ").presence || "Terreno ##{id}"
    else
      [edificio_nome.presence, unidade_numero.presence && "Un. #{unidade_numero}", street].compact_blank.join(" — ").presence || "Captação ##{id}"
    end
  end
end
