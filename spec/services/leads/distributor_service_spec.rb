require 'rails_helper'

RSpec.describe Leads::DistributorService do
  include ActiveSupport::Testing::TimeHelpers

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

  describe "filtro de origem" do
    it "nao captura lead de site quando a regra nao habilita origem site" do
      rule = create(:distribution_rule, source_site: false, source_webhook: true)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)

      lead = build_lead(origin: "site")
      described_class.find_and_distribute(lead)

      expect(lead.reload.admin_user_id).to be_nil
      expect(lead.distribution_rule_id).to be_nil
    end

    it "nao trata origem meta como site quando a regra so habilita site" do
      rule = create(:distribution_rule, source_site: true, source_meta: false)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)

      lead = build_lead(origin: "facebook")
      described_class.find_and_distribute(lead)

      expect(lead.reload.admin_user_id).to be_nil
      expect(lead.distribution_rule_id).to be_nil
    end

    it "distribui origem meta quando a regra habilita meta" do
      rule = create(:distribution_rule, source_site: false, source_meta: true)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)

      lead = build_lead(origin: "facebook")
      described_class.find_and_distribute(lead)

      expect(lead.reload.admin_user_id).to eq(agent_without_checkin.id)
      expect(lead.distribution_rule_id).to eq(rule.id)
    end
  end

  describe "represamento por agenda" do
    it "usa a chave interna do dia da semana, independente do locale do servidor" do
      travel_to Time.zone.local(2026, 6, 26, 8, 0, 0) do
        schedule = DistributionRule::DAYS.index_with do
          { "active" => "false", "start" => "09:00", "end" => "18:00" }
        end
        schedule["fri"] = { "active" => "true", "start" => "09:00", "end" => "18:00" }
        rule = create(:distribution_rule, represamento_active: true, represamento_schedule: schedule)
        create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)

        lead = build_lead(origin: "site")
        described_class.find_and_distribute(lead)

        expect(lead.reload.status).to eq("Represado")
        expect(lead.admin_user_id).to be_nil
        expect(lead.distribution_rule_id).to eq(rule.id)
      end
    end
  end

  describe "tipo de negocio" do
    it "mantem lead ambiguo elegivel para regra de venda" do
      rule = create(:distribution_rule, business_type: :venda, source_site: false, source_meta: true)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)

      lead = build_lead(origin: "facebook", product: "Lead Meta sem modalidade")
      described_class.find_and_distribute(lead)

      expect(lead.reload.admin_user_id).to eq(agent_without_checkin.id)
      expect(lead.distribution_rule_id).to eq(rule.id)
    end

    it "mantem lead ambiguo elegivel para regra de locacao" do
      rule = create(:distribution_rule, business_type: :locacao, source_site: false, source_meta: true)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)

      lead = build_lead(origin: "facebook", product: "Lead Meta sem modalidade")
      described_class.find_and_distribute(lead)

      expect(lead.reload.admin_user_id).to eq(agent_without_checkin.id)
      expect(lead.distribution_rule_id).to eq(rule.id)
    end

    it "nao envia lead explicitamente de venda para regra de locacao" do
      rule = create(:distribution_rule, business_type: :locacao, source_site: false, source_meta: true)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)

      lead = build_lead(origin: "facebook", product: "Comprar apartamento")
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

  describe "modo performance" do
    it "escolhe o candidato pelo maior score ponderado por peso" do
      low_weight_agent = create(:admin_user, :field_agent)
      high_weight_agent = create(:admin_user, :field_agent)
      rule = create(:distribution_rule, distribution_mode: :performance)
      low_weight = create(:distribution_rule_agent, distribution_rule: rule, admin_user: low_weight_agent, weight: 1)
      high_weight = create(:distribution_rule_agent, distribution_rule: rule, admin_user: high_weight_agent, weight: 5)

      allow(rule).to receive(:rand).and_return(0.30, 0.30)

      expect(rule.next_available_agent([low_weight, high_weight])).to eq(high_weight)
    end

    it "distribui para o agente selecionado pelo modo performance" do
      low_weight_agent = create(:admin_user, :field_agent)
      high_weight_agent = create(:admin_user, :field_agent)
      rule = create(:distribution_rule, distribution_mode: :performance)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: low_weight_agent, weight: 1)
      high_weight_rule_agent = create(:distribution_rule_agent, distribution_rule: rule, admin_user: high_weight_agent, weight: 5)
      allow_any_instance_of(DistributionRule).to receive(:rand).and_return(0.30, 0.30)
      allow(Leads::NotificationDispatcher).to receive(:deliver)

      lead = build_lead
      described_class.find_and_distribute(lead)

      expect(lead.reload.admin_user_id).to eq(high_weight_agent.id)
      expect(lead.status).to eq(Lead.status_value(:waiting_acceptance))
      expect(high_weight_rule_agent.reload.last_lead_received_at).to be_present
      expect(Leads::NotificationDispatcher).to have_received(:deliver)
    end
  end

  describe "modo shark tank" do
    it "deixa o lead aguardando aceite sem dono e notifica apenas candidatos elegiveis por check-in" do
      rule = create(:distribution_rule, distribution_mode: :shark_tank, require_active_checkin: true, notify_push: true)
      eligible = create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_with_checkin)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)
      allow(Leads::NotificationDispatcher).to receive(:notify_shark_tank)

      lead = build_lead
      described_class.find_and_distribute(lead)

      lead.reload
      expect(lead.admin_user_id).to be_nil
      expect(lead.status).to eq(Lead.status_value(:waiting_acceptance))
      expect(lead.activities.where(kind: "shark_tank_ready")).to exist
      expect(Leads::NotificationDispatcher).to have_received(:notify_shark_tank) do |notified_lead, notified_rule, candidates:|
        expect(notified_lead.id).to eq(lead.id)
        expect(notified_rule.id).to eq(rule.id)
        expect(candidates.pluck(:id)).to eq([eligible.id])
      end
    end

    it "nao libera Shark Tank quando exige check-in e nao ha candidato elegivel" do
      rule = create(:distribution_rule, distribution_mode: :shark_tank, require_active_checkin: true)
      create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent_without_checkin)
      allow(Leads::NotificationDispatcher).to receive(:notify_shark_tank)

      lead = build_lead
      result = described_class.find_and_distribute(lead)

      expect(result).to be_nil
      expect(lead.reload.admin_user_id).to be_nil
      expect(lead.status).to eq(Lead.default_status)
      expect(lead.distribution_rule_id).to be_nil
      expect(Leads::NotificationDispatcher).not_to have_received(:notify_shark_tank)
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
