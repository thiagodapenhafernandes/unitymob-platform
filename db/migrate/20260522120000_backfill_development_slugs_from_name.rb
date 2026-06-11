require "set"

class BackfillDevelopmentSlugsFromName < ActiveRecord::Migration[7.1]
  class MigrationHabitation < ApplicationRecord
    self.table_name = "habitations"
  end

  def up
    used_slugs = MigrationHabitation.where.not(slug: [nil, ""]).pluck(:slug).to_set

    MigrationHabitation.where(tipo: "Empreendimento").find_each do |habitation|
      base = habitation.nome_empreendimento.presence || habitation.titulo_anuncio.presence
      next if base.blank?

      current_slug = habitation.slug.to_s
      used_slugs.delete(current_slug)

      slug = unique_slug(base.parameterize, habitation.codigo, used_slugs)
      next if slug.blank? || slug == current_slug

      habitation.update_columns(slug: slug, updated_at: Time.current)
      used_slugs.add(slug)
    end
  end

  def down
    say "Backfill de slugs de empreendimento não é reversível automaticamente."
  end

  private

  def unique_slug(base_slug, code, used_slugs)
    return "" if base_slug.blank?
    return base_slug unless used_slugs.include?(base_slug)

    code_suffix = code.to_s.parameterize
    return "#{base_slug}-#{code_suffix}" if code_suffix.present? && !used_slugs.include?("#{base_slug}-#{code_suffix}")

    suffix = 2
    suffix += 1 while used_slugs.include?("#{base_slug}-#{suffix}")
    "#{base_slug}-#{suffix}"
  end
end
