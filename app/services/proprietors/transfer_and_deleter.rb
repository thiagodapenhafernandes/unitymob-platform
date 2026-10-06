# frozen_string_literal: true

module Proprietors
  # Exclui um proprietário transferindo seus imóveis para outro proprietário
  # da mesma conta. Histórico (interações, agendamentos, interesses) é
  # desvinculado via `dependent: :nullify`, nunca transferido nem apagado.
  class TransferAndDeleter
    Error = Class.new(StandardError)

    Result = Struct.new(:habitations_count, keyword_init: true)

    def self.call(proprietor:, target:)
      new(proprietor:, target:).call
    end

    def initialize(proprietor:, target:)
      @proprietor = proprietor
      @target = target
    end

    def call
      validate!

      habitations_count = 0
      Proprietor.transaction do
        habitations_count = @proprietor.habitations.update_all(proprietor_id: @target.id)
        @proprietor.destroy!
      end

      Result.new(habitations_count: habitations_count)
    end

    private

    def validate!
      raise Error, "Proprietário não encontrado." if @proprietor.nil?
      raise Error, "Escolha outro proprietário para receber os imóveis." if @target.nil?
      raise Error, "Escolha outro proprietário para receber os imóveis." if @target.id == @proprietor.id
      raise Error, "O proprietário destino pertence a outra conta." if @target.tenant_id != @proprietor.tenant_id
      if @proprietor.vista_code.present?
        raise Error, "Este proprietário é sincronizado pela Vista e não pode ser excluído por aqui."
      end
    end
  end
end
