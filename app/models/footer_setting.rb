class FooterSetting < ApplicationRecord
  include TenantScoped
  include PhoneNormalizable

  has_many :footer_links, dependent: :destroy
  has_many :footer_stores, dependent: :destroy
  has_many :footer_social_links, dependent: :destroy

  normalize_phone_fields :whatsapp

  accepts_nested_attributes_for :footer_links, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :footer_stores, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :footer_social_links, allow_destroy: true, reject_if: :all_blank
  def self.instance(tenant: Current.tenant || Tenant.public_for)
    raise ArgumentError, "Tenant obrigatório para configurações do rodapé" if tenant.blank?

    defaults = {
      about_title: tenant.name,
      about_text: "Encontre oportunidades imobiliárias e fale com nossa equipe.",
      links_title: "Links Rápidos",
      stores_title: "Nossas Lojas",
      contact_title: "Contato",
      social_title: "Redes Sociais",
      copyright_text: "© #{Time.current.year} #{tenant.name}. Todos os direitos reservados."
    }
    where(tenant: tenant).first_or_create!(defaults)
  end
end
