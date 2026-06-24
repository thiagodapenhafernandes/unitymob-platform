require 'rails_helper'

RSpec.describe Leads::DistributorService do
  let(:store) { create(:store) }
  let(:agent_with_checkin) { create(:admin_user, :field_agent) }
  let(:agent_without_checkin) { create(:admin_user, :field_agent) }

  before do
    # agent_with_checkin tem check-in ativo na loja
    create(:check_in, admin_user: agent_with_checkin, store: store, status: :active, checked_in_at: 5.minutes.ago)
    # Testamos DistributorService em isolação, sem o callback after_create_commit
    Lead.skip_callback(:commit, :after, :route_lead)
  end

  after { Lead.set_callback(:commit, :after, :route_lead) }

  def build_lead(attrs = {})
    Lead.create!(attrs.reverse_merge(name: "Cliente Teste", phone: "11999999999", origin: "site"))
  end

  describe "retrocompatibilidade (flags default off)" do
    it "distribui normalmente quando regra não exige check-in, mesmo sem corretor logado" do
      rule = create(:distribution_rule, require_active_checkin: false)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)

      lead = build_lead
      described_class.find_and_distribute(lead)

      expect(lead.reload.admin_user_id).to eq(agent_without_checkin.id)
      expect(lead.status).to eq("Aguardando Aceite")
    end
  end

  describe "webhook_tags" do
    it "distribui lead de webhook quando a tag da regra confere" do
      rule = create(:distribution_rule, source_site: false, source_webhook: true, webhook_tags: ["elite"])
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)

      lead = build_lead(origin: "webhook", other_information: { "webhook_tags" => ["elite"] })
      described_class.find_and_distribute(lead)

      expect(lead.reload.admin_user_id).to eq(agent_without_checkin.id)
      expect(lead.distribution_rule_id).to eq(rule.id)
    end

    it "ignora regra de webhook quando as tags não conferem" do
      rule = create(:distribution_rule, source_site: false, source_webhook: true, webhook_tags: ["elite"])
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)

      lead = build_lead(origin: "webhook", other_information: { "webhook_tags" => ["popular"] })
      described_class.find_and_distribute(lead)

      expect(lead.reload.admin_user_id).to be_nil
      expect(lead.distribution_rule_id).to be_nil
    end
  end

  describe "require_active_checkin=true" do
    it "entrega lead apenas para corretor com check-in ativo" do
      rule = create(:distribution_rule, require_active_checkin: true)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_with_checkin)

      lead = build_lead
      described_class.find_and_distribute(lead)

      expect(lead.reload.admin_user_id).to eq(agent_with_checkin.id)
    end

    it "filtra por checkin_store_ids quando setado" do
      outra_loja = create(:store, name: "Outra")
      rule = create(:distribution_rule, require_active_checkin: true, checkin_store_ids: [outra_loja.id])
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_with_checkin)

      lead = build_lead
      described_class.find_and_distribute(lead)

      # agent_with_checkin está na loja `store`, não em `outra_loja` → não elegível
      expect(lead.reload.admin_user_id).to be_nil
    end

    it "aceita múltiplas lojas em checkin_store_ids" do
      loja_b = create(:store, name: "Loja B")
      rule = create(:distribution_rule, require_active_checkin: true, checkin_store_ids: [store.id, loja_b.id])
      dra = create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_with_checkin)

      expect(rule.candidates_filtered_by_checkin.pluck(:id)).to eq([dra.id])
    end

    context "sem candidatos elegíveis + represamento_active" do
      it "deixa lead represado com razão no_eligible_agent_with_checkin" do
        rule = create(:distribution_rule,
                      require_active_checkin: true,
                      represamento_active: true)
        create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)

        lead = build_lead
        described_class.find_and_distribute(lead)

        lead.reload
        expect(lead.status).to eq("Represado")
        activity = lead.activities.where(kind: "dammed").last
        expect(activity).to be_present
        expect(activity.metadata["reason"]).to eq("no_eligible_agent_with_checkin")
      end
    end
  end

  describe "DistributionRule#candidates_filtered_by_checkin" do
    it "retorna todos os agentes quando flag off (retrocompat)" do
      rule = create(:distribution_rule, require_active_checkin: false)
      dra1 = create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_with_checkin)
      dra2 = create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)

      expect(rule.candidates_filtered_by_checkin.pluck(:id)).to match_array([dra1.id, dra2.id])
    end

    it "filtra apenas agents com check-in ativo quando flag on" do
      rule = create(:distribution_rule, require_active_checkin: true)
      dra1 = create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_with_checkin)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)

      expect(rule.candidates_filtered_by_checkin.pluck(:id)).to eq([dra1.id])
    end

    context "require_inside_radius" do
      it "exclui check-ins com out_of_radius_since setado" do
        # O check-in de agent_with_checkin saiu do raio (ainda não foi auto-checkout)
        agent_with_checkin.active_check_in.update_column(:out_of_radius_since, 30.seconds.ago)
        rule = create(:distribution_rule, require_active_checkin: true, require_inside_radius: true)
        create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_with_checkin)

        expect(rule.candidates_filtered_by_checkin).to be_empty
      end

      it "inclui check-ins sem saída de raio registrada" do
        rule = create(:distribution_rule, require_active_checkin: true, require_inside_radius: true)
        dra = create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_with_checkin)

        expect(rule.candidates_filtered_by_checkin.pluck(:id)).to eq([dra.id])
      end
    end

    context "require_active_shift" do
      let(:today_wday) { Time.current.in_time_zone("America/Sao_Paulo").wday }

      it "inclui quando turno vinculado está ativo agora" do
        shift = create(:store_shift,
                       admin_user: agent_with_checkin,
                       store: store,
                       day_of_week: today_wday,
                       start_time: 1.hour.ago.strftime("%H:%M"),
                       end_time: 2.hours.from_now.strftime("%H:%M"))
        agent_with_checkin.active_check_in.update!(store_shift: shift)

        rule = create(:distribution_rule, require_active_checkin: true, require_active_shift: true)
        dra = create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_with_checkin)

        expect(rule.candidates_filtered_by_checkin.pluck(:id)).to eq([dra.id])
      end

      it "exclui quando turno vinculado já terminou (janela até auto_checkout_after_minutes)" do
        # Turno começou há 3h e terminou há 1h, mas auto-checkout cron só fechou em até 60min
        shift = create(:store_shift,
                       admin_user: agent_with_checkin,
                       store: store,
                       day_of_week: today_wday,
                       start_time: 3.hours.ago.strftime("%H:%M"),
                       end_time: 1.hour.ago.strftime("%H:%M"))
        agent_with_checkin.active_check_in.update!(store_shift: shift)

        rule = create(:distribution_rule, require_active_checkin: true, require_active_shift: true)
        create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_with_checkin)

        expect(rule.candidates_filtered_by_checkin).to be_empty
      end

      it "para check-in manual (sem store_shift), busca turno ativo do corretor na loja" do
        # Check-in manual → store_shift_id = nil
        agent_with_checkin.active_check_in.update!(store_shift: nil)
        create(:store_shift,
               admin_user: agent_with_checkin,
               store: store,
               day_of_week: today_wday,
               start_time: 1.hour.ago.strftime("%H:%M"),
               end_time: 2.hours.from_now.strftime("%H:%M"))

        rule = create(:distribution_rule, require_active_checkin: true, require_active_shift: true)
        dra = create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_with_checkin)

        expect(rule.candidates_filtered_by_checkin.pluck(:id)).to eq([dra.id])
      end

      it "exclui manual sem nenhum turno ativo agora" do
        agent_with_checkin.active_check_in.update!(store_shift: nil)
        # Sem nenhum store_shift criado → nenhum turno ativo
        rule = create(:distribution_rule, require_active_checkin: true, require_active_shift: true)
        create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_with_checkin)

        expect(rule.candidates_filtered_by_checkin).to be_empty
      end
    end
  end
end
