class BackfillDomGabrielDevelopmentNames < ActiveRecord::Migration[7.1]
  DOM_GABRIEL_CODES = {
    "1550" => "Edifício Dom Gabriel",
    "1801" => "Edifício Dom Gabriel",
    "2290" => "Edifício Dom Gabriel",
    "2315" => "Edifício Dom Gabriel",
    "2694" => "Edifício Dom Gabriel",
    "3052" => "Edifício Dom Gabriel",
    "3102" => "Edifício Dom Gabriel",
    "3186" => "Edifício Dom Gabriel",
    "3403" => "Edifício Dom Gabriel",
    "3705" => "Edifício Dom Gabriel",
    "3754" => "Edifício Dom Gabriel",
    "4255" => "Edificio Dom Gabriel",
    "4550" => "Edificio Dom Gabriel",
    "4722" => "Edifício Dom Gabriel",
    "5233" => "Edifício Dom Gabriel",
    "6576" => "Edifício Dom Gabriel",
    "6744" => "Edifício Dom Gabriel",
    "7174" => "Edifício Dom Gabriel",
    "7298" => "Edifício Dom Gabriel",
    "7841" => "Edifício Dom Gabriel",
    "8272" => "Edifício Dom Gabriel",
    "8388" => "Edifício Dom Gabriel"
  }.freeze

  def up
    now = Time.current

    say_with_time "Backfilling Dom Gabriel Vista unit development names" do
      DOM_GABRIEL_CODES.sum do |codigo, name|
        update(<<~SQL.squish)
          UPDATE habitations
          SET nome_empreendimento = #{connection.quote(name)},
              codigo_empreendimento = NULL,
              updated_at = #{connection.quote(now)}
          WHERE codigo = #{connection.quote(codigo)}
        SQL
      end
    end

    say_with_time "Clearing stale Dom Gabriel development name from non-development property 8282" do
      update(<<~SQL.squish)
        UPDATE habitations
        SET nome_empreendimento = NULL,
            codigo_empreendimento = NULL,
            updated_at = #{connection.quote(now)}
        WHERE codigo = '8282'
          AND categoria = 'Terreno Comercial'
      SQL
    end
  end

  def down
    # Data correction only. Do not restore stale or missing development names.
  end
end
