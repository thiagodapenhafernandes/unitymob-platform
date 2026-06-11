class AddIntroTextToSeoSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :seo_settings, :intro_text, :text
  end
end
