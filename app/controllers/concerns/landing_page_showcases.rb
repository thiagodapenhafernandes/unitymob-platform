# Monta o resultado de cada bloco "Vitrine de imóveis" de uma página. Usado pela página pública e pela prévia
# do admin: só a vitrine interativa recebe a paginação (?page=) e os filtros do visitante.
module LandingPageShowcases
  extend ActiveSupport::Concern

  private

  def build_showcases(blocks, habitations:)
    blocks.select { |block| block.block_type == "property_showcase" }.to_h do |block|
      interactive = block.interactive_showcase?
      showcase = LandingPages::Showcase.new(
        scope: habitations,
        block: block,
        visitor_params: (interactive ? LandingPages::Showcase.permitted_visitor_params(params) : {}),
        page: (interactive ? params[:page] : 1)
      )
      [block.object_id, showcase.call]
    end
  end
end
