# Contas novas nascem no tema "default". A migration 20260814121000 pulava a
# troca do padrão da coluna quando o usuário do banco não era dono da tabela,
# podendo deixar "saluteimoveis" como padrão em produção. Esta é idempotente:
# só mexe se o padrão atual não for "default". O model também fixa o padrão
# (Tenant: attribute :public_site_theme), então a aplicação não depende disto.
# Contas existentes mantêm o tema escolhido.
class EnsureDefaultPublicSiteTheme < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    return unless column_exists?(:tenants, :public_site_theme)

    current = connection.columns(:tenants).find { _1.name == "public_site_theme" }&.default
    if current == "default"
      say "tenants.public_site_theme já tem padrão 'default'"
      return
    end

    begin
      change_column_default :tenants, :public_site_theme, from: current, to: "default"
    rescue ActiveRecord::StatementInvalid => error
      raise unless insufficient_privilege?(error)

      say "AVISO: sem permissão para alterar o padrão de tenants.public_site_theme (atual: #{current.inspect}). " \
          "O model Tenant já garante 'default' para contas novas; peça ao dono da tabela para rodar: " \
          "ALTER TABLE tenants ALTER COLUMN public_site_theme SET DEFAULT 'default'"
    end
  end

  def down
    # Irreversível de propósito: não há padrão anterior correto para restaurar.
  end

  private

  def insufficient_privilege?(error)
    error.cause.is_a?(PG::InsufficientPrivilege) || error.message.include?("must be owner of table tenants")
  end
end
