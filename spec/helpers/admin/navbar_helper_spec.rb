require "rails_helper"

RSpec.describe Admin::NavbarHelper, type: :helper do
  describe "#admin_contextbar_back_path" do
    let(:request_context) do
      instance_double(
        ActionDispatch::Request,
        host: "dev.unitymob.com.br",
        port: 443,
        referer: nil,
        fullpath: "/admin/whatsapp/disparos/2",
        path: "/admin/whatsapp/disparos/2"
      )
    end

    before do
      allow(helper).to receive(:request).and_return(request_context)
    end

    it "prioriza return_to interno preservando query string" do
      allow(helper).to receive(:params).and_return(
        return_to: "/admin/whatsapp/disparos?whatsapp_sender_number_id=1&page=2"
      )

      expect(helper.admin_contextbar_back_path).to eq("/admin/whatsapp/disparos?whatsapp_sender_number_id=1&page=2")
    end

    it "aceita URL absoluta do mesmo host e converte para path interno" do
      allow(helper).to receive(:params).and_return(
        return_to: "https://dev.unitymob.com.br/admin/leads?view=kanban"
      )

      expect(helper.admin_contextbar_back_path).to eq("/admin/leads?view=kanban")
    end

    it "bloqueia retorno para host externo" do
      allow(helper).to receive(:params).and_return(return_to: "https://example.com/admin/leads")

      expect(helper.admin_contextbar_back_path).to be_nil
    end

    it "usa referer interno quando return_to nao existe" do
      allow(helper).to receive(:params).and_return({})
      allow(request_context).to receive(:referer).and_return("https://dev.unitymob.com.br/admin/whatsapp/disparos?whatsapp_sender_number_id=1")

      expect(helper.admin_contextbar_back_path).to eq("/admin/whatsapp/disparos?whatsapp_sender_number_id=1")
    end

    it "nao gera voltar para a propria pagina" do
      allow(helper).to receive(:params).and_return(return_to: "/admin/whatsapp/disparos/2")

      expect(helper.admin_contextbar_back_path).to be_nil
    end
  end
end
