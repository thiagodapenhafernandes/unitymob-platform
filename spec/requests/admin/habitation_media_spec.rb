require "rails_helper"
require "tempfile"

RSpec.describe "Admin::HabitationMedia", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "media-admin-#{SecureRandom.hex(8)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o conteúdo do modal de mídia com o mesmo manager do módulo" do
    habitation = create(:habitation, codigo: "MEDIA-MODAL-#{SecureRandom.hex(6)}")
    habitation.photos.attach(io: StringIO.new("foto um"), filename: "um.jpg", content_type: "image/jpeg")
    habitation.photos.attach(io: StringIO.new("foto dois"), filename: "dois.jpg", content_type: "image/jpeg")

    get modal_admin_habitation_media_path(habitation), headers: { "X-Requested-With" => "XMLHttpRequest" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-media-modal__header--compact")
    expect(response.body).to include("ax-media-manager--compact")
    expect(response.body).to include("Configurações de mídia")
    expect(response.body).to include("photo-upload")
    expect(response.body).to include("draggable-item")
    expect(response.body).to include("media-photo-drag-handle")
    expect(response.body).to include("data-photo-upload-async-submit=\"true\"")
    expect(response.body).to include(upload_admin_habitation_media_path(habitation, format: :json))
  end

  it "salva mídia por JSON e devolve payload para manter o modal na tela" do
    habitation = create(:habitation, codigo: "MEDIA-SAVE-#{SecureRandom.hex(6)}")
    habitation.photos.attach(io: StringIO.new("foto existente"), filename: "existente.jpg", content_type: "image/jpeg")
    attachment = habitation.photos.attachments.first

    patch admin_habitation_media_path(habitation), params: {
      habitation: {
        foto_classificacao: "Boas",
        ordered_photo_ids: attachment.id.to_s,
        tour_virtual: "https://example.com/tour-360",
        videos: ["https://example.com/video"]
      }
    }, headers: { "Accept" => "application/json", "X-Requested-With" => "XMLHttpRequest" }

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    habitation.reload

    expect(payload["ok"]).to eq(true)
    expect(payload["gallery_html"]).to include("attached-photo-item")
    expect(payload.dig("counts", "total")).to eq(1)
    expect(payload.dig("inputs", "ordered_photo_ids")).to eq(attachment.id.to_s)
    expect(habitation.tour_virtual).to eq("https://example.com/tour-360")
  end

  it "expõe o gatilho do modal dentro da aba de mídia da edição" do
    habitation = create(:habitation, codigo: "MEDIA-EDIT-#{SecureRandom.hex(6)}")

    get edit_admin_habitation_path(habitation, anchor: "media")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Abrir organizador de mídia")
    expect(response.body).to include(modal_admin_habitation_media_path(habitation))
  end

  it "expõe o gatilho do modal no menu de ações do catálogo" do
    habitation = create(:habitation, codigo: "MEDIA-CARD-#{SecureRandom.hex(6)}")

    get admin_habitations_path(ownership: "all")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Mídia e uploads")
    expect(response.body).to include(modal_admin_habitation_media_path(habitation))
  end

  it "envia foto por JSON e devolve a galeria renderizada sem depender do submit do cadastro" do
    habitation = create(:habitation, codigo: "MEDIA-UP-#{SecureRandom.hex(6)}")
    uploaded_photo = Tempfile.new(["media-upload", ".jpg"])
    uploaded_photo.write("foto nova")
    uploaded_photo.rewind

    post upload_admin_habitation_media_path(habitation, format: :json), params: {
      habitation: {
        photos: [Rack::Test::UploadedFile.new(uploaded_photo.path, "image/jpeg")]
      }
    }

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    habitation.reload

    expect(payload["ok"]).to eq(true)
    expect(payload["gallery_html"]).to include("attached-photo-item")
    expect(payload.dig("counts", "photos")).to eq(1)
    expect(payload.dig("inputs", "ordered_photo_ids")).to eq(habitation.photos.attachments.first.id.to_s)
    expect(habitation.photos.attachments.size).to eq(1)
  ensure
    uploaded_photo&.close
    uploaded_photo&.unlink
  end

  it "reordena fotos por JSON e devolve hidden fields consistentes" do
    habitation = create(:habitation, codigo: "MEDIA-ORDER-#{SecureRandom.hex(6)}")
    habitation.photos.attach(io: StringIO.new("foto um"), filename: "um.jpg", content_type: "image/jpeg")
    habitation.photos.attach(io: StringIO.new("foto dois"), filename: "dois.jpg", content_type: "image/jpeg")
    attachments = habitation.photos.attachments.order(:id).to_a

    patch reorder_admin_habitation_media_path(habitation, format: :json), params: {
      habitation: {
        ordered_photo_ids: attachments.reverse.map(&:id).join(",")
      }
    }

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)

    expect(payload["gallery_html"]).to include(%(data-id="#{attachments.second.id}"))
    expect(payload.dig("inputs", "ordered_photo_ids")).to eq(attachments.reverse.map(&:id).join(","))
    expect(habitation.reload.photo_ids_order).to eq(attachments.reverse.map(&:id))
  end

  it "atualiza visibilidade de fotos e imagens da API por JSON" do
    habitation = create(
      :habitation,
      codigo: "MEDIA-VIS-#{SecureRandom.hex(6)}",
      pictures: [
        { "url" => "https://example.com/site.jpg" },
        { "url" => "https://example.com/interna.jpg" }
      ]
    )
    habitation.photos.attach(io: StringIO.new("foto local"), filename: "foto-local.jpg", content_type: "image/jpeg")
    attachment = habitation.photos.attachments.first

    patch visibility_admin_habitation_media_path(habitation, format: :json), params: {
      habitation: {
        site_hidden_photo_ids: attachment.id.to_s,
        site_hidden_picture_urls: "https://example.com/interna.jpg"
      }
    }

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    habitation.reload

    expect(payload.dig("inputs", "site_hidden_photo_ids")).to eq(attachment.id.to_s)
    expect(payload.dig("inputs", "site_hidden_picture_urls")).to eq("https://example.com/interna.jpg")
    expect(habitation.site_hidden_photo_ids).to contain_exactly(attachment.id)
    expect(habitation.pictures.second["site_hidden"]).to eq(true)
  end

  it "remove foto anexada por JSON e devolve a galeria atualizada" do
    habitation = create(:habitation, codigo: "MEDIA-DEL-#{SecureRandom.hex(6)}")
    habitation.photos.attach(io: StringIO.new("foto um"), filename: "um.jpg", content_type: "image/jpeg")
    habitation.photos.attach(io: StringIO.new("foto dois"), filename: "dois.jpg", content_type: "image/jpeg")
    attachments = habitation.photos.attachments.order(:id).to_a

    delete destroy_photo_admin_habitation_media_path(habitation, format: :json), params: {
      photo_id: attachments.first.id
    }

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    habitation.reload

    expect(payload["gallery_html"]).not_to include(%(data-id="#{attachments.first.id}"))
    expect(payload["gallery_html"]).to include(%(data-id="#{attachments.second.id}"))
    expect(habitation.photos.attachments.map(&:id)).to contain_exactly(attachments.second.id)
  end
end
