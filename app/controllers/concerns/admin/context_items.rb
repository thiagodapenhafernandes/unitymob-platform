module Admin::ContextItems
  extend ActiveSupport::Concern

  MAX_CONTEXT_ITEMS = 8

  TRACKABLE_ACTIONS = {
    "admin/habitations" => %w[show edit],
    "admin/habitation_media" => %w[show],
    "admin/habitation_intakes" => %w[show edit],
    "admin/proprietors" => %w[edit],
    "admin/leads" => %w[show],
    "admin/proposals" => %w[edit],
    "admin/whatsapp_inbox" => %w[show]
  }.freeze

  included do
    helper_method :admin_context_items
    after_action :remember_admin_context_item_from_response, if: :admin_context_trackable_response?
  end

  def admin_context_items
    admin_context_skip_once_item_keys

    # Os pins de acesso rápido devem aparecer em TODAS as telas do admin, não só
    # nas de detalhe. A exibição usa apenas o que já está na sessão (hidratado);
    # o registro da página atual continua restrito às ações trackable
    # (current_admin_context_item_for_render / remember_admin_context_item_from_response).
    entries = Array(session[:admin_context_items]).filter_map do |entry|
      hydrate_admin_context_item(entry)
    end

    if (current_item = current_admin_context_item_for_render)
      entries = merge_admin_context_item(entries, current_item)
    end

    session[:admin_context_items] = entries.map { |entry| entry.except(:record).stringify_keys }
    entries
  end

  def forget_admin_context_item(key)
    skip_admin_context_item_once(key)
    session[:admin_context_items] = Array(session[:admin_context_items]).reject do |entry|
      entry.to_h["key"].to_s == key.to_s
    end
  end

  def clear_admin_context_items
    skip_admin_context_items_once(Array(session[:admin_context_items]).filter_map { |entry| entry.to_h["key"] })
    session.delete(:admin_context_items)
  end

  private

  def admin_context_trackable_response?
    admin_context_trackable_request? && response.successful?
  end

  def admin_context_trackable_request?
    request.get? &&
      request.format.html? &&
      TRACKABLE_ACTIONS.fetch(controller_path, []).include?(action_name)
  end

  def remember_admin_context_item_from_response
    record = admin_context_record_from_assigns
    item = build_admin_context_item(record)
    return unless item
    return if skip_admin_context_item_once?(item[:key])

    entries = Array(session[:admin_context_items])
    session[:admin_context_items] = merge_admin_context_item(entries, item).map { |entry| entry.except(:record).stringify_keys }
  end

  def current_admin_context_item_for_render
    return unless admin_context_trackable_request?

    record = admin_context_record_from_assigns
    item = build_admin_context_item(record)
    return unless item
    return if skip_admin_context_item_once?(item[:key])
    return unless admin_context_record_allowed?(item[:type], record)

    item.merge(record: record)
  end

  def merge_admin_context_item(entries, item)
    normalized_entries = entries.map { |entry| entry.to_h.symbolize_keys }
    [item, *normalized_entries.reject { |entry| entry[:key] == item[:key] }].first(MAX_CONTEXT_ITEMS)
  end

  def skip_admin_context_item_once(key)
    key = key.to_s
    return if key.blank?

    skip_admin_context_items_once([key])
  end

  def skip_admin_context_items_once(keys)
    keys = Array(keys).map(&:to_s).reject(&:blank?)
    return if keys.blank?

    current_keys = Array(session[:admin_context_skip_once_item_keys]).map(&:to_s)
    session[:admin_context_skip_once_item_keys] = (keys + current_keys).uniq.first(50)
  end

  def skip_admin_context_item_once?(key)
    admin_context_skip_once_item_keys.include?(key.to_s)
  end

  def admin_context_skip_once_item_keys
    @admin_context_skip_once_item_keys ||= Array(session.delete(:admin_context_skip_once_item_keys)).map(&:to_s)
  end

  def admin_context_record_from_assigns
    [
      defined?(@habitation) && @habitation,
      defined?(@proprietor) && @proprietor,
      defined?(@lead) && @lead,
      defined?(@proposal) && @proposal,
      defined?(@conversation) && @conversation
    ].find { |record| record.respond_to?(:persisted?) && record.persisted? }
  end

  def hydrate_admin_context_item(entry)
    entry = entry.to_h
    record = find_admin_context_record(entry["type"], entry["id"])
    return unless record
    return unless admin_context_record_allowed?(entry["type"], record)

    build_admin_context_item(record)&.merge(record: record)
  end

  def find_admin_context_record(type, id)
    return if id.blank?

    case type.to_s
    when "habitation"
      Habitation.find_by(id: id)
    when "proprietor"
      Proprietor.find_by(id: id)
    when "lead"
      Lead.find_by(id: id)
    when "proposal"
      Proposal.find_by(id: id)
    when "whatsapp_conversation"
      WhatsappConversation.find_by(id: id)
    end
  end

  def build_admin_context_item(record)
    case record
    when Habitation
      {
        key: "habitation:#{record.id}",
        type: "habitation",
        id: record.id,
        label: admin_context_habitation_label(record),
        path: edit_admin_habitation_path(record),
        icon: "bi-building",
        tone: "property"
      }
    when Proprietor
      {
        key: "proprietor:#{record.id}",
        type: "proprietor",
        id: record.id,
        label: admin_context_label(record.name, fallback: "Proprietário ##{record.id}"),
        path: edit_admin_proprietor_path(record),
        icon: "bi-person-vcard",
        tone: "owner"
      }
    when Lead
      {
        key: "lead:#{record.id}",
        type: "lead",
        id: record.id,
        label: admin_context_label(record.display_name, record.name, fallback: "Lead ##{record.id}"),
        path: admin_lead_path(record),
        icon: "bi-megaphone",
        tone: "lead"
      }
    when Proposal
      {
        key: "proposal:#{record.id}",
        type: "proposal",
        id: record.id,
        label: admin_context_label(record.title, fallback: "Proposta ##{record.id}"),
        path: edit_admin_proposal_path(record),
        icon: "bi-file-earmark-text",
        tone: "proposal"
      }
    when WhatsappConversation
      {
        key: "whatsapp_conversation:#{record.id}",
        type: "whatsapp_conversation",
        id: record.id,
        label: admin_context_label(record.display_name, fallback: "WhatsApp ##{record.id}"),
        path: admin_whatsapp_conversation_path(record),
        icon: "bi-whatsapp",
        tone: "whatsapp"
      }
    end
  end

  def admin_context_record_allowed?(type, record)
    case type.to_s
    when "habitation"
      admin_context_habitation_allowed?(record)
    when "proprietor"
      current_admin_user&.admin?
    when "lead"
      admin_context_lead_allowed?(record)
    when "proposal"
      admin_context_proposal_allowed?(record)
    when "whatsapp_conversation"
      admin_context_whatsapp_conversation_allowed?(record)
    else
      false
    end
  end

  def admin_context_habitation_allowed?(habitation)
    return false unless can?(:view, :imoveis)
    ids = accessible_owner_ids(:imoveis)
    return true if ids.nil?
    return true if ids.include?(habitation.admin_user_id)
    return true if habitation.broker_assignments.exists?(admin_user_id: ids)

    broker_name = current_admin_user&.name.to_s.strip
    broker_name.present? && habitation.corretor_nome.to_s.downcase.include?(broker_name.downcase)
  end

  def admin_context_lead_allowed?(lead)
    return false unless can?(:view, :leads)

    owner_in_scope?(:leads, lead.admin_user_id)
  end

  def admin_context_proposal_allowed?(proposal)
    return false unless can?(:view, :comercial)

    owner_in_scope?(:comercial, proposal.admin_user_id, proposal.lead&.admin_user_id)
  end

  def admin_context_whatsapp_conversation_allowed?(conversation)
    return false unless can?(:view, :whatsapp_inbox)

    owner_in_scope?(:whatsapp_inbox, conversation.assigned_admin_user_id, conversation.lead&.admin_user_id)
  end

  def admin_context_habitation_label(habitation)
    code = habitation.codigo.to_s.strip
    return "Imóvel #{code}" if code.present?

    admin_context_label(habitation.titulo_anuncio, habitation.nome_empreendimento, fallback: "Imóvel ##{habitation.id}")
  end

  def admin_context_label(*values, fallback:)
    values.map(&:to_s).map(&:strip).find(&:present?) || fallback
  end
end
