class HabitationPhotoSharesController < ApplicationController
  before_action :noindex

  # GET /fotos/:token — galeria pública das fotos selecionadas por um corretor.
  # O token é a credencial; sem login. Isolamento por tenant via habitation.
  def show
    @share = HabitationPhotoShare.find_by(token: params[:token])

    unless @share&.valid_for_access?
      return render :invalid, status: :gone, layout: false
    end

    @habitation = @share.habitation
    @photo_urls = @share.selected_image_urls

    @share.register_view!

    render :show, layout: false
  end

  private

  def noindex
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end
end
