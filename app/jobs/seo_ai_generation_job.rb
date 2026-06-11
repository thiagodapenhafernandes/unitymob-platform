class SeoAiGenerationJob < ApplicationJob
  queue_as :default

  def perform(seo_setting_id)
    seo_setting = SeoSetting.find_by(id: seo_setting_id)
    return if seo_setting.blank?
    return if seo_setting.manual_mode?
    return unless Ai::SeoContentService.connected?

    Ai::SeoContentService.new(seo_setting).generate!
  end
end
