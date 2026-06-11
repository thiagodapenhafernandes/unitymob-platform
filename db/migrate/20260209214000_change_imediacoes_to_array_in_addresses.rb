class ChangeImediacoesToArrayInAddresses < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      UPDATE addresses AS a
      SET imediacoes = h.imediacoes
      FROM habitations AS h
      WHERE a.addressable_type = 'Habitation'
        AND a.addressable_id = h.id
        AND (a.imediacoes IS NULL OR btrim(a.imediacoes) = '')
        AND h.imediacoes IS NOT NULL
        AND btrim(h.imediacoes) <> '';
    SQL

    change_column :addresses,
                  :imediacoes,
                  :text,
                  array: true,
                  using: "regexp_split_to_array(COALESCE(imediacoes, ''), E'[,;\\n\\r]+')"

    execute <<~SQL
      UPDATE addresses
      SET imediacoes = COALESCE(
        (
          SELECT array_agg(item)
          FROM (
            SELECT DISTINCT btrim(regexp_replace(value, '\\s+', ' ', 'g')) AS item
            FROM unnest(addresses.imediacoes) AS value
            WHERE btrim(value) <> ''
          ) normalized
        ),
        '{}'::text[]
      );
    SQL

    change_column_default :addresses, :imediacoes, from: nil, to: []
    change_column_null :addresses, :imediacoes, false
  end

  def down
    change_column :addresses,
                  :imediacoes,
                  :text,
                  array: false,
                  default: nil,
                  null: true,
                  using: "array_to_string(imediacoes, ', ')"
  end
end
