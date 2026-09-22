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

  describe "trilha do contextbar" do
    let(:request_context) do
      instance_double(ActionDispatch::Request, host: "dev.unitymob.com.br", port: 443, referer: "https://dev.unitymob.com.br/admin", fullpath: "/admin/habitations", path: "/admin/habitations")
    end

    before do
      helper.extend(Admin::SidebarHelper)
      allow(helper).to receive(:request).and_return(request_context)
      allow(helper).to receive(:params).and_return({})
      allow(helper).to receive(:controller_name).and_return("habitations")
      allow(helper).to receive(:controller_path).and_return("admin/habitations")
    end

    it "na listagem mostra Seção › Módulo, sem Início e sem Voltar por referer" do
      allow(helper).to receive(:action_name).and_return("index")

      html = helper.admin_contextbar_breadcrumb

      expect(html).to include("ax-breadcrumb__section", "Produto")
      expect(html).to include("<strong>Imóveis</strong>")
      expect(html).not_to include("Início")
      expect(helper.admin_contextbar_back_path).to be_nil
    end

    it "em página interna linka o módulo e nomeia a ação; Voltar usa o referer" do
      allow(helper).to receive(:action_name).and_return("edit")

      html = helper.admin_contextbar_breadcrumb

      expect(html).to include('class="ax-breadcrumb__module"', "Imóveis", "<strong>Editar</strong>")
      expect(helper.admin_contextbar_back_path).to eq("/admin")
    end
  end
end
