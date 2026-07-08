class AddStickyAssignmentExpressionIndexesToLeads < ActiveRecord::Migration[7.1]
  # Fidelização (Leads::StickyAssignment) roda a cada lead distribuído com
  # regexp_replace/lower sobre os leads do tenant. As expressões abaixo casam
  # EXATAMENTE com o SQL do serviço (phone_sql/email_sql em
  # app/services/leads/sticky_assignment.rb) — tenant_id vem à frente porque o
  # escopo é sempre @lead.tenant.leads. O planner combina os ramos do OR via
  # BitmapOr entre os índices.
  INDEXES = {
    "index_leads_on_tenant_and_phone_digits" =>
      %q{(tenant_id, regexp_replace(coalesce(phone, ''), '\D', '', 'g'))},
    "index_leads_on_tenant_and_client_phone_digits" =>
      %q{(tenant_id, regexp_replace(coalesce(client_phone, ''), '\D', '', 'g'))},
    "index_leads_on_tenant_and_email_lower" =>
      %q{(tenant_id, lower(coalesce(email, '')))},
    "index_leads_on_tenant_and_client_email_lower" =>
      %q{(tenant_id, lower(coalesce(client_email, '')))}
  }.freeze

  def up
    INDEXES.each do |name, expression|
      execute "CREATE INDEX IF NOT EXISTS #{name} ON leads #{expression}"
    end
  end

  def down
    INDEXES.each_key do |name|
      execute "DROP INDEX IF EXISTS #{name}"
    end
  end
end
