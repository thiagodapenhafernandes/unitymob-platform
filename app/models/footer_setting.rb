class FooterSetting < ApplicationRecord
  has_many :footer_links, dependent: :destroy
  has_many :footer_stores, dependent: :destroy
  has_many :footer_social_links, dependent: :destroy

  accepts_nested_attributes_for :footer_links, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :footer_stores, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :footer_social_links, allow_destroy: true, reject_if: :all_blank
  def self.instance
    first_or_create!(
      about_title: "Salute Imóveis",
      about_text: "Sua imobiliária de confiança em Balneário Camboriú. Tradição e excelência no mercado imobiliário desde sempre.",
      links_title: "Links Rápidos",
      stores_title: "Nossas Lojas",
      contact_title: "Contato",
      social_title: "Redes Sociais",
      whatsapp: "(47) 98863-0198",
      email: "contato@saluteimoveis.com",
      copyright_text: "© 2026 Salute Imóveis. Todos os direitos reservados. CRECI 6834"
    )
  end
end
