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
    return [] if current_admin_user&.system_admin? && current_tenant.blank?

    admin_context_skip_once_item_keys
    normalize_admin_context_session_items

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
      entry = entry.to_h
      entry["key"].to_s == key.to_s && admin_context_entry_scoped_to_current_user?(entry)
    end
  end

  def clear_admin_context_items
    entries = Array(session[:admin_context_items]).map(&:to_h)
    skip_admin_context_items_once(entries.select { |entry| admin_context_entry_scoped_to_current_user?(entry) }.filter_map { |entry| entry["key"] })
    session[:admin_context_items] = entries.reject { |entry| admin_context_entry_scoped_to_current_user?(entry) }
    session.delete(:admin_context_items) if Array(session[:admin_context_items]).blank?
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
    item = current_admin_context_item_for_render
    return unless item

    entries = Array(session[:admin_context_items]).filter_map do |entry|
      hydrate_admin_context_item(entry)
    end
    session[:admin_context_items] = merge_admin_context_item(entries, item).map { |entry| entry.except(:record).stringify_keys }
  end

  def current_admin_context_item_for_render
    return unless admin_context_trackable_request?

    record = admin_context_record_from_assigns
    item = build_admin_context_item(record)
    return unless item
    return if skip_admin_context_item_once?(item[:key])
    return unless admin_context_record_allowed?(item[:type], record)

    item.merge(record: record, admin_user_id: current_admin_user&.id)
  end

  def merge_admin_context_item(entries, item)
    normalized_entries = entries.map { |entry| entry.to_h.symbolize_keys }
    existing_index = normalized_entries.index { |entry| entry[:key] == item[:key] }

    if existing_index
      normalized_entries[existing_index] = normalized_entries[existing_index].merge(item)
      normalized_entries.first(MAX_CONTEXT_ITEMS)
    else
      [*normalized_entries, item].last(MAX_CONTEXT_ITEMS)
    end
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
    scoped_keys = keys.map { |key| admin_context_scoped_key(key) }
    session[:admin_context_skip_once_item_keys] = (scoped_keys + current_keys).uniq.first(50)
  end

  def skip_admin_context_item_once?(key)
    admin_context_skip_once_item_keys.include?(admin_context_scoped_key(key))
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
    return unless admin_context_entry_for_current_user?(entry)

    record = find_admin_context_record(entry["type"], entry["id"])
    return unless record
    return unless admin_context_record_allowed?(entry["type"], record)

    build_admin_context_item(record)&.merge(record: record, admin_user_id: current_admin_user&.id)
  end

  def normalize_admin_context_session_items
    entries = Array(session[:admin_context_items]).map(&:to_h)
    return if entries.blank?

    scoped_entries = entries.select { |entry| admin_context_entry_for_current_user?(entry) }
    session[:admin_context_items] = scoped_entries
    session.delete(:admin_context_items) if scoped_entries.blank?
  end

  def admin_context_entry_for_current_user?(entry)
    current_user_id = current_admin_user&.id
    return false if current_user_id.blank?

    entry.to_h["admin_user_id"].to_s == current_user_id.to_s
  end

  def admin_context_entry_scoped_to_current_user?(entry)
    current_user_id = current_admin_user&.id
    return false if current_user_id.blank?

    entry_user_id = entry.to_h["admin_user_id"].to_s
    entry_user_id.blank? || entry_user_id == current_user_id.to_s
  end

  def admin_context_scoped_key(key)
    "#{current_admin_user&.id}:#{key}"
  end

  def find_admin_context_record(type, id)
    return if id.blank?
    return if current_tenant.blank?

    case type.to_s
    when "habitation"
      current_tenant.habitations.find_by(id: id)
    when "proprietor"
      current_tenant.proprietors.find_by(id: id)
    when "lead"
      current_tenant.leads.find_by(id: id)
    when "proposal"
      Proposal.joins(:lead).where(leads: { tenant_id: current_tenant.id }).find_by(id: id)
    when "whatsapp_conversation"
      current_tenant.whatsapp_conversations.find_by(id: id)
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
      can?(:view, :proprietarios)
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
