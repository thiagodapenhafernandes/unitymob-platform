module Api
  module V1
    module BrowserExtension
      class LeadsController < BaseController
        before_action :require_terms!
        def resolve
          phone = Phones::Normalizer.call(params[:contact_phone].to_s.first(40))
          return render json: { leads: [] } unless phone

          variants = [phone]
          variants << phone.delete_prefix("55") if phone.start_with?("55") && phone.length.in?([12, 13])
          matches = lead_scope.where(
            "regexp_replace(coalesce(leads.phone, ''), '\\D', '', 'g') IN (:phones) OR " \
            "regexp_replace(coalesce(leads.client_phone, ''), '\\D', '', 'g') IN (:phones)", phones: variants
          ).includes(:admin_user).order(updated_at: :desc).limit(11).to_a
          render json: { contact_phone: phone, leads: matches.first(10).map { |lead| summary(lead) }, more: matches.size > 10 }
        end

        def search_properties
          lead = lead_scope.find(params[:id])
          query = params[:q].to_s.strip
          purpose = params[:purpose].to_s
          return render json: {error: "invalid_fields"}, status: :unprocessable_entity unless query.length <= 100 && %w[venda locacao].include?(purpose)
          scope = purpose == "venda" ? property_scope.for_sale : property_scope.for_rent
          scope = scope.admin_search_text(query) if query.present?
          rows = scope.includes(:address).order(updated_at: :desc).limit(21).to_a
          linked_ids = lead.property_interests.pluck(:habitation_id) + [lead.property_id]
          render json: { properties: rows.first(20).map { |p| {id: p.id, code: p.codigo, title: p.display_title,
            city: p.cidade, neighborhood: p.bairro, price_cents: purpose == "venda" ? p.valor_venda_cents : p.valor_locacao_cents,
            linked: linked_ids.include?(p.id)} }, more: rows.length > 20 }
        end

        def show
          lead = lead_scope.find(params[:id])
          property_ids = lead.property_interests.limit(30).pluck(:habitation_id)
          property_ids << lead.property_id if lead.property_id
          properties = grant.tenant.habitations.where(id: property_ids.uniq).includes(:address).limit(30)
          appointments = proposals = []
          tasks = if grant.admin_user.can?(:view, :comercial)
            ids = grant.admin_user.owns_all?(:comercial) ? nil :
              (grant.admin_user.can_view_team?(:comercial) ? grant.admin_user.team_scope_ids : [grant.admin_user_id])
            appointments = grant.tenant.appointments.where(lead_id: lead.id).upcoming
            proposals = lead.proposals.ordered
            appointments = appointments.where(admin_user_id: ids) if ids
            proposals = proposals.where(admin_user_id: ids) if ids
            scope = grant.tenant.tasks.where(lead_id: lead.id).pendentes
            scope = scope.where(admin_user_id: ids) if ids
            scope.ordered
          else
            []
          end
          notes = grant.tenant.lead_activities.where(lead_id: lead.id, kind: "note").recent
          render json: {
            lead: summary(lead),
            status_options: grant.capabilities[:change_status] ? available_status_stages(lead).map { |stage| {id: stage.id, name: stage.name, color: stage.display_color} } : [],
            unsuccessful_attempts: lead.unsuccessful_attempt_count,
            appointments_count: appointments.size,
            appointments: appointments.first(20).map { |item| { id: item.id, title: item.title, kind: item.kind_label, starts_at: item.starts_at.iso8601 } },
            proposals_count: proposals.size,
            proposals: proposals.first(20).map { |item| { id: item.id, status: item.status_label, created_at: item.created_at.iso8601 } },
            labels: lead.labels_for(grant.admin_user).where(tenant_id: grant.tenant_id).map { |label| { id: label.id, name: label.name, color: label.color } },
            label_catalog: grant.admin_user.lead_labels.where(tenant_id: grant.tenant_id).ordered.map { |label| { id: label.id, name: label.name, color: label.color } },
            notes_count: notes.count,
            notes: notes.limit(20).map { |note| { id: note.id, body: note.meta("body").to_s.first(5000),
              author: note.meta("by").to_s.first(200), kind: LeadActivity::CONTACT_KIND_LABELS[note.meta("contact_kind")] || "Anotação interna",
              created_at: note.created_at.iso8601 } },
            tasks_count: tasks.size,
            properties: properties.map { |property| { id: property.id, code: property.codigo, title: property.display_title, city: property.cidade, neighborhood: property.bairro } },
            tasks: tasks.first(20).map { |task| { id: task.id, title: task.title, kind: task.kind_label, priority: task.priority_label, due_at: task.due_at&.iso8601 } }
          }
        end

        private

        def require_terms!
          render json: { error: "terms_required" }, status: :forbidden unless grant.terms_accepted?
        end

        def summary(lead)
          { id: lead.id, name: lead.display_name, status: lead.status, stage_id: lead.lead_pipeline_stage_id,
            owner_name: lead.admin_user&.tenant_id == grant.tenant_id ? lead.admin_user.name : nil,
            origin: lead.origin, created_at: lead.created_at&.iso8601 }
        end
      end
    end
  end
end
