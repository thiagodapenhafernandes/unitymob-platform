module AdminUsers
  # Hard-delete de um AdminUser com reatribuição segura de todas as referências.
  #
  # Política explícita por (tabela, coluna). A cobertura é verificada por introspecção
  # contra TODAS as FKs reais que apontam para admin_users: se surgir uma FK nova não
  # classificada, levanta erro (evita perda de dado silenciosa ou destroy bloqueado).
  class HardDeleter
    Error = Class.new(StandardError)

    # FKs removidas por migração (auditorias append-only) — id histórico permanece.
    DROPPED_FK = {
      "data_export_audit_logs" => %w[admin_user_id],
      "checkin_audit_logs"     => %w[admin_user_id actor_admin_user_id]
    }.freeze

    # Já tratadas pelo `dependent:` do model AdminUser — não mexemos aqui.
    MODEL_HANDLED = {
      "access_control_rules"  => %w[admin_user_id],   # dependent: :nullify
      "check_ins"             => %w[admin_user_id],   # dependent: :destroy
      "habitation_share_links" => %w[admin_user_id],  # dependent: :destroy
      "store_shifts"          => %w[admin_user_id],   # dependent: :destroy
      "stores"                => %w[director_admin_user_id], # directed_stores dependent: :nullify
      "trusted_devices"       => %w[admin_user_id],   # dependent: :destroy
      # Perna secundária da FK COMPOSTA (manager_id, tenant_id) → admin_users:
      # a introspecção desdobra as duas colunas; o NULLIFY de manager_id resolve
      # a constraint — tenant_id jamais é alterado aqui.
      "admin_users"           => %w[tenant_id]
    }.freeze

    # Propriedade/carteira de trabalho → transferida para o admin destino.
    REASSIGN = {
      "appointments"               => %w[admin_user_id],
      "captacoes"                  => %w[corretor_id],
      "client_property_interests"  => %w[admin_user_id],
      "crm_appointments"           => %w[admin_user_id],
      "habitations"                => %w[admin_user_id],
      "leads"                      => %w[admin_user_id],
      "marketing_campaigns"        => %w[admin_user_id],
      "proposals"                  => %w[admin_user_id],
      "tasks"                      => %w[admin_user_id],
      "whatsapp_campaigns"         => %w[created_by_id] # campanha é ativo da conta
    }.freeze

    # Dados pessoais/operacionais do usuário → apagados.
    DESTROY = {
      # Convite multi-conta: a associação morre com o titular (primary) OU com o
      # espelho (member) — sem qualquer dos dois lados ela não faz sentido. Os
      # refs de auditoria (invited_by/revoked_by) e manager são NULLIFY abaixo.
      "account_memberships"          => %w[primary_admin_user_id member_admin_user_id],
      "distribution_rule_agents"     => %w[admin_user_id],
      "habitation_broker_assignments" => %w[admin_user_id],
      "habitation_exports"           => %w[admin_user_id], # arquivos de export do usuário (auditoria própria não tem FK)
      "inbound_webhook_tokens"       => %w[admin_user_id], # credencial pessoal: morre com o usuário
      "lead_labels"                  => %w[admin_user_id], # etiquetas privadas (labelings limpas antes)
      "location_pings"               => %w[admin_user_id],
      "manual_checkin_requests"      => %w[admin_user_id],
      "push_delivery_events"         => %w[admin_user_id], # telemetria de push
      "push_subscriptions"           => %w[admin_user_id],
      "user_meta_integrations"       => %w[admin_user_id]
    }.freeze

    # Referências secundárias/atores → nulificadas (histórico preservado sem dono).
    NULLIFY = {
      "access_control_rules"          => %w[created_by_id],
      # primary_admin_user_id (auto-ref do espelho): nulificar orfaniza os
      # espelhos do usuário excluído em OUTRAS contas com segurança — DESTROY
      # deletaria o admin_user espelho e orfanaria os dados dele no tenant
      # convidado (fora do alcance da reatribuição, que é single-tenant).
      "admin_users"                   => %w[manager_id rentals_manager_id primary_admin_user_id],
      # Convite multi-conta: snapshot do gestor + atores de auditoria do convite.
      "account_memberships"           => %w[manager_id rentals_manager_id invited_by_id revoked_by_id],
      "ai_property_suggestions"       => %w[admin_user_id],
      "client_interactions"           => %w[admin_user_id],
      "habitation_interactions"       => %w[admin_user_id],
      "habitations"                   => %w[admin_reviewed_by_id],
      "leads"                         => %w[shared_by_admin_user_id],
      "manual_checkin_requests"       => %w[reviewed_by_admin_user_id],
      "photography_schedule_blocks"   => %w[created_by_id],
      "property_settings"             => %w[broker_capture_fallback_admin_user_id],
      "seo_change_logs"               => %w[admin_user_id],
      "seo_redirects"                 => %w[created_by_admin_user_id],
      "trusted_devices"               => %w[created_by_id],
      "whatsapp_business_integrations" => %w[connected_by_admin_user_id],
      "whatsapp_conversations"        => %w[assigned_admin_user_id],
      "whatsapp_messages"             => %w[admin_user_id],
      "automation_workflows"          => %w[created_by_id],
      "automation_workflow_versions"  => %w[created_by_id published_by_id],
      # cartões pessoais viram órfãos invisíveis (available_for exige dono ou
      # system); DELETE quebraria a FK de whatsapp_messages.presentation_card_id
      "presentation_cards"            => %w[admin_user_id],
      "whatsapp_campaign_recipients"  => %w[admin_user_id],
      "whatsapp_campaign_unsubscribes" => %w[reenabled_by_id]
    }.freeze

    def self.call(user:, target:)
      new(user, target).call
    end

    def initialize(user, target)
      @user = user
      @target = target
    end

    def call
      raise Error, "Usuário destino é obrigatório para reatribuição." if @target.nil?
      raise Error, "Escolha um usuário destino diferente do excluído." if @target.id == @user.id

      verify_coverage!

      ActiveRecord::Base.transaction do
        REASSIGN.each { |table, cols| cols.each { |col| update_col(table, col, @target.id) } }
        NULLIFY.each  { |table, cols| cols.each { |col| update_col(table, col, nil) } }
        delete_lead_labelings_of_user_labels # antes de lead_labels (FK sem cascade)
        DESTROY.each  { |table, cols| cols.each { |col| delete_rows(table, col) } }
        @user.destroy!
      end
      true
    end

    private

    def conn
      ActiveRecord::Base.connection
    end

    def update_col(table, col, value)
      value_sql = value.nil? ? "NULL" : conn.quote(value)
      conn.update(
        "UPDATE #{conn.quote_table_name(table)} SET #{conn.quote_column_name(col)} = #{value_sql} " \
        "WHERE #{conn.quote_column_name(col)} = #{conn.quote(@user.id)}"
      )
    end

    # lead_labelings referencia lead_labels sem ON DELETE CASCADE: limpa as
    # aplicações das etiquetas privadas do usuário antes de apagar as etiquetas.
    def delete_lead_labelings_of_user_labels
      conn.delete(
        "DELETE FROM lead_labelings WHERE lead_label_id IN "         "(SELECT id FROM lead_labels WHERE admin_user_id = #{conn.quote(@user.id)})"
      )
    end

    def delete_rows(table, col)
      conn.delete(
        "DELETE FROM #{conn.quote_table_name(table)} WHERE #{conn.quote_column_name(col)} = #{conn.quote(@user.id)}"
      )
    end

    # Garante que toda FK real para admin_users está classificada em algum mapa.
    def verify_coverage!
      covered = [DROPPED_FK, MODEL_HANDLED, REASSIGN, DESTROY, NULLIFY]
                .flat_map { |map| map.flat_map { |table, cols| cols.map { |col| [table, col] } } }
                .to_set
      uncovered = current_fk_columns.to_set - covered
      return if uncovered.empty?

      raise Error, "FKs para admin_users não classificadas no HardDeleter: " \
                   "#{uncovered.to_a.map { |t, c| "#{t}.#{c}" }.join(', ')}. Atualize AdminUsers::HardDeleter."
    end

    def current_fk_columns
      sql = <<~SQL
        SELECT rel.relname AS tbl, att.attname AS col
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_class ref ON ref.oid = con.confrelid
        JOIN unnest(con.conkey) WITH ORDINALITY AS k(attnum, ord) ON true
        JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = k.attnum
        WHERE con.contype = 'f' AND ref.relname = 'admin_users'
      SQL
      conn.exec_query(sql).rows.map { |tbl, col| [tbl, col] }
    end
  end
end
