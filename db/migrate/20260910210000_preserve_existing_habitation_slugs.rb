class PreserveExistingHabitationSlugs < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      INSERT INTO friendly_id_slugs (slug, sluggable_id, sluggable_type, created_at)
      SELECT h.slug, h.id, 'Habitation', CURRENT_TIMESTAMP
      FROM habitations h
      WHERE NULLIF(h.slug, '') IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM friendly_id_slugs s
          WHERE s.sluggable_type = 'Habitation' AND s.sluggable_id = h.id AND s.slug = h.slug
        )
    SQL
  end

  def down
    # Não descarta o histórico de URLs no rollback.
  end
end
