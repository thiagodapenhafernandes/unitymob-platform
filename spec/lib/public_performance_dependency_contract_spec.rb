require "rails_helper"

RSpec.describe "public performance dependency contract" do
  let(:photo_gallery_controller) { Rails.root.join("app/javascript/controllers/photo_gallery_controller.js").read }
  let(:property_carousel_controller) { Rails.root.join("app/javascript/controllers/property_carousel_controller.js").read }
  let(:phone_input_controller) { Rails.root.join("app/javascript/controllers/phone_input_controller.js").read }
  let(:controllers_index) { Rails.root.join("app/javascript/controllers/index.js").read }
  let(:card_swiper_controller) { Rails.root.join("app/javascript/controllers/card_swiper_controller.js").read }
  let(:public_layout) { Rails.root.join("app/views/layouts/application.html.erb").read }

  it "mantém Swiper fora do bundle público inicial nos carrosséis pesados" do
    expect(photo_gallery_controller).not_to include('import Swiper from "swiper/bundle"')
    expect(property_carousel_controller).not_to include('import Swiper from "swiper/bundle"')

    expect(photo_gallery_controller).to include('import("swiper/bundle")')
    expect(property_carousel_controller).to include('import("swiper/bundle")')
    expect(property_carousel_controller).to include("IntersectionObserver")
  end

  it "carrega o CSS do Swiper junto com o controller em vez de no head público" do
    expect(public_layout).not_to include("swiper-bundle.min.css")

    [card_swiper_controller, photo_gallery_controller, property_carousel_controller].each do |source|
      expect(source).to include("data-swiper-css")
      expect(source).to include("swiper-bundle.min.css")
    end
  end

  it "não baixa intl-tel-input nem CSS externo no connect do telefone público" do
    connect_body = phone_input_controller[/connect\(\) \{(?<body>.*?)\n  \}/m, :body]

    expect(connect_body).to be_present
    expect(connect_body).not_to include("loadStylesheet()")
    expect(phone_input_controller).not_to include("\n  initialize()")
    expect(phone_input_controller).to include("ensureEnhancedInput()")
    expect(phone_input_controller).to include("initializeIntlTelInput()")
    expect(phone_input_controller).to include("shouldAutoEnhance()")
    expect(phone_input_controller).to include('closest("#quickProprietorModal")')
    expect(phone_input_controller).to include('phone-input:enhance')
    expect(phone_input_controller).to include('import("intl-tel-input")')
  end

  it "registra phone-input no bundle admin sem baixar a biblioteca internacional no boot" do
    expect(controllers_index).to include('import PhoneInputController from "controllers/phone_input_controller"')
    expect(controllers_index).to include('application.register("phone-input", PhoneInputController)')
    expect(controllers_index).not_to include('import("intl-tel-input")')
    expect(controllers_index).not_to include("intl-tel-input@")
  end
end
