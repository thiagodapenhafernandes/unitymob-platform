class LegacyPublicRoutesController < ApplicationController
  LEGACY_LISTING_PREFIXES = {
    "venda" => :venda_path,
    "alugar" => :aluguel_path,
    "aluguel" => :aluguel_path,
    "festival-salute" => :root_path,
    "imovel" => :root_path,
    "empreendimento" => :empreendimentos_path
  }.freeze

  SUSPICIOUS_SEGMENT = %r{(?:https?:|www\.|[a-z0-9-]+\.(?:com|net|org|io|dev|app)(?:\.[a-z]{2})?)(?:/|\z)}i
  FILE_EXTENSION = /\.(?:css|js|map|json|xml|txt|ico|png|jpe?g|gif|svg|webp|woff2?|ttf|php)\z/i

  skip_before_action :load_layout_settings

  def show
    return head :not_found if suspicious_request?

    if (target = property_target || listing_target)
      redirect_to target, status: :moved_permanently
    else
      head :not_found
    end
  end

  private

  def legacy_path
    @legacy_path ||= params[:path].to_s.delete_prefix("/")
  end

  def suspicious_request?
    request.path.match?(SUSPICIOUS_SEGMENT) || request.path.match?(FILE_EXTENSION)
  end

  def property_target
    return unless legacy_path.start_with?("imovel/", "empreendimento/")

    identifier = legacy_path[/([0-9]+)\z/, 1]
    return if identifier.blank?

    scope = public_tenant.habitations
    habitation = scope.find_by(codigo: identifier) || scope.find_by(id: identifier)
    return unless habitation&.publicly_viewable?

    habitation_path(habitation)
  end

  def listing_target
    prefix = legacy_path.split("/", 2).first
    route_helper = LEGACY_LISTING_PREFIXES[prefix]
    return if route_helper.blank?

    public_send(route_helper)
  end
end
