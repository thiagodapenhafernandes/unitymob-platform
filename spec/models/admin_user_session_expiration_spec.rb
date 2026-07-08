require "rails_helper"

# Expiração de sessão configurável por conta: timeout de inatividade por
# tenant, cap do "lembrar deste dispositivo" e epoch de "Encerrar todas as
# sessões". Colunas do tenant são stubadas (guards has_attribute?) para a spec
# rodar mesmo antes da migration 20260707000002.
RSpec.describe "Expiração de sessão por conta" do
  let(:user) { create(:admin_user) }
  let(:tenant) { user.tenant }

  def stub_session_columns(timeout_enabled: false, timeout_days: nil, remember_days: nil, epoch_at: nil)
    allow(tenant).to receive(:has_attribute?).and_call_original
    allow(tenant).to receive(:has_attribute?).with(:session_timeout_enabled).and_return(true)
    allow(tenant).to receive(:has_attribute?).with(:session_remember_days).and_return(true)
    allow(tenant).to receive(:has_attribute?).with(:session_epoch_at).and_return(true)
    allow(tenant).to receive(:session_timeout_enabled?).and_return(timeout_enabled)
    allow(tenant).to receive(:session_timeout_days).and_return(timeout_days)
    allow(tenant).to receive(:session_remember_days).and_return(remember_days)
    allow(tenant).to receive(:session_epoch_at).and_return(epoch_at)
  end

  describe "#timeout_in" do
    it "é nil sem configuração da conta (pré-migration/default) e sem tenant" do
      expect(user.timeout_in).to be_nil
      expect(build(:admin_user, super_admin: true).timeout_in).to be_nil
    end

    it "usa os dias configurados quando o tenant habilita o timeout" do
      stub_session_columns(timeout_enabled: true, timeout_days: 10)
      expect(user.timeout_in).to eq(10.days)
    end

    it "é nil quando o tenant desabilita o timeout" do
      stub_session_columns(timeout_enabled: false, timeout_days: 10)
      expect(user.timeout_in).to be_nil
    end
  end

  describe "cap do lembrar deste dispositivo" do
    it "usa o padrão do Devise sem configuração da conta" do
      stub_session_columns
      expect(user.remember_expires_at).to be_within(1.minute).of(AdminUser.remember_for.from_now)
    end

    it "limita o cookie em session_remember_days" do
      stub_session_columns(remember_days: 30)
      expect(user.remember_expires_at).to be_within(1.minute).of(30.days.from_now)
    end

    it "invalida no servidor tokens gerados antes da janela da conta" do
      stub_session_columns(remember_days: 30)
      user.remember_created_at = 60.days.ago
      token = user.rememberable_value

      expect(user.remember_me?(token, 40.days.ago.utc)).to be(false) # válido pro Devise (6 meses), barrado pelo cap
      expect(user.remember_me?(token, 1.day.ago.utc)).to be(true)
    end

    it "o timeout de inatividade também limita o lembrar (login sempre lembra o dispositivo)" do
      stub_session_columns(timeout_enabled: true, timeout_days: 7)
      user.remember_created_at = 60.days.ago
      token = user.rememberable_value

      expect(user.remember_expires_at).to be_within(1.minute).of(7.days.from_now)
      expect(user.remember_me?(token, 8.days.ago.utc)).to be(false)
    end
  end

  describe "AdminSessionEpoch (Encerrar todas as sessões)" do
    it "derruba sessão sem carimbo ou carimbada antes do epoch" do
      stub_session_columns(epoch_at: 1.hour.ago)

      expect(AdminSessionEpoch.expired?(user, {})).to be(true)
      expect(AdminSessionEpoch.expired?(user, { "signed_in_at" => 2.hours.ago.to_i })).to be(true)
    end

    it "preserva sessão re-carimbada depois do epoch" do
      stub_session_columns(epoch_at: 1.hour.ago)

      session_data = {}
      AdminSessionEpoch.stamp!(session_data)
      expect(AdminSessionEpoch.expired?(user, session_data)).to be(false)
    end

    it "não derruba nada sem epoch configurado (ou pré-migration)" do
      stub_session_columns(epoch_at: nil)
      expect(AdminSessionEpoch.expired?(user, {})).to be(false)
    end
  end
end
