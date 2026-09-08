module Api
  module V1
    module BrowserExtension
      class LeadsController < BaseController
        include HabitationQuickFilters
        rescue_from ArgumentError, with: -> { render json: {error: "invalid_fields"}, status: :unprocessable_entity }
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

        def share_properties
          lead_scope.find(params[:id])
          return render json: {error: "forbidden"}, status: :forbidden unless grant.capabilities[:link_properties]

          ids = params[:ids]
          raise ArgumentError unless ids.is_a?(Array) && ids.length.between?(1, 20) && ids.all? { |id| id.to_s.match?(/\A[1-9]\d*\z/) }
          ids = ids.map(&:to_i).uniq
          properties = property_scope.where(id: ids, exibir_no_site_flag: true, status: Habitation::PUBLIC_STATUSES)
            .includes(photos_attachments: :blob).to_a
          raise ActiveRecord::RecordNotFound unless properties.length == ids.length

          render json: {public_origin: grant.tenant.public_base_url(fallback_base_url: request.base_url),
            properties: properties.map { |property| {id: property.id, code: property.codigo, title: property.display_title,
              city: property.cidade, neighborhood: property.bairro, public_path: property_path(property.codigo),
              photo_urls: property.public_image_sources.filter_map { |source| Storage::PublicCdnImageUrl.resolve(source) }.first(1)} }}
        end

        def search_properties
          lead = lead_scope.find(params[:id])
          catalog = ::BrowserExtension::PropertyCatalog.new(scope: property_scope, user: grant.admin_user, params: catalog_params)
          scope = catalog.call
          linked_ids = (lead.property_interests.pluck(:habitation_id) + [lead.property_id]).compact
          # Legacy clients expect linked properties to be omitted.
          scope = scope.where.not(id: linked_ids) unless params[:catalog] == true
          total = scope.except(:order).count
          page = Integer(params[:page].presence || 1)
          raise ArgumentError unless page.between?(1, 10000)
          rows = scope.includes(:address, :admin_user, photos_attachments: :blob).offset((page - 1) * 20).limit(21).to_a
          purpose = params[:purpose].to_s
          development_names = grant.tenant.habitations.where(codigo: rows.map(&:codigo_empreendimento).compact_blank)
            .pluck(:codigo, :nome_empreendimento).to_h
          render json: { properties: rows.first(20).map { |p| {id: p.id, code: p.codigo, title: p.display_title,
            city: p.cidade, neighborhood: p.bairro, price_cents: purpose == "locacao" || params[:facet] == "locacao" || !p.valor_venda_cents.to_i.positive? ? p.valor_locacao_cents : p.valor_venda_cents,
            card_title: p.nome_empreendimento.presence || development_names[p.codigo_empreendimento].presence || [p.categoria.presence || "Imóvel", p.bairro.presence || p.cidade.presence].compact.join(" em "),
            bedrooms: p.dormitorios_qtd, suites: p.suites_qtd, parking: p.vagas_qtd, area: p.public_area_m2,
            condo_cents: p.valor_condominio_cents, iptu_cents: p.valor_iptu_cents, rental: purpose == "locacao" || params[:facet] == "locacao" || !p.valor_venda_cents.to_i.positive?,
            photo_urls: p.public_image_sources.filter_map { |source| Storage::PublicCdnImageUrl.resolve(source) }.first(100),
            owner: p.admin_user&.tenant_id == grant.tenant_id ? p.admin_user.name : nil,
            public_path: p.exibir_no_site_flag && Habitation::PUBLIC_STATUSES.include?(p.status) ? property_path(p.codigo) : nil,
            linked: linked_ids.include?(p.id)} }, more: rows.length > 20, total: total, page: page, counts: params[:catalog] == true ? catalog.counts : nil,
            filter_options: params[:include_options] == true ? catalog.options : nil }
        end

        def show
          lead = lead_scope.find(params[:id])
          property_ids = lead.property_interests.limit(30).pluck(:habitation_id)
          property_ids << lead.property_id if lead.property_id
          properties = grant.tenant.habitations.where(id: property_ids.uniq).includes(:address, photos_attachments: :blob).limit(30)
          development_names = grant.tenant.habitations.where(codigo: properties.map(&:codigo_empreendimento).compact_blank)
            .pluck(:codigo, :nome_empreendimento).to_h
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
            contact_options: {
              kinds: LeadActivity::CONTACT_KIND_LABELS.except("note").merge("nota" => "Nota interna"),
              results: LeadActivity::CONTACT_RESULT_LABELS,
              attempt_kinds: LeadActivity::CONTACT_ATTEMPT_KINDS
            },
            notes_count: notes.count,
            notes: notes.limit(20).map { |note| { id: note.id, body: note.meta("body").to_s.first(5000),
              author: note.meta("by").to_s.first(200), kind: LeadActivity::CONTACT_KIND_LABELS[note.meta("contact_kind")] || "Anotação interna",
              result: LeadActivity::CONTACT_RESULT_LABELS[note.meta("contact_result")],
              created_at: note.created_at.iso8601 } },
            tasks_count: tasks.size,
            property_categories: property_scope.where.not(categoria: [nil, ""]).distinct.order(:categoria).pluck(:categoria),
            property_quick_filters: HabitationQuickFilters::QUICK_FILTERS,
            public_origin: grant.tenant.public_base_url(fallback_base_url: request.base_url),
            properties: properties.map { |property| { photo_urls: property.public_image_sources.filter_map { |source| Storage::PublicCdnImageUrl.resolve(source) }.first(100), removable: lead.property_id != property.id, public_path: property.exibir_no_site_flag && Habitation::PUBLIC_STATUSES.include?(property.status) ? property_path(property.codigo) : nil, id: property.id, code: property.codigo, title: property.display_title,
              card_title: property.nome_empreendimento.presence || development_names[property.codigo_empreendimento].presence || [property.categoria.presence || "Imóvel", property.bairro.presence || property.cidade.presence].compact.join(" em "),
              bedrooms: property.dormitorios_qtd, suites: property.suites_qtd, parking: property.vagas_qtd, area: property.public_area_m2,
              price_cents: property.valor_venda_cents.to_i.positive? ? property.valor_venda_cents : property.valor_locacao_cents,
              rental: !property.valor_venda_cents.to_i.positive? && property.valor_locacao_cents.to_i.positive?,
              condo_cents: property.valor_condominio_cents, iptu_cents: property.valor_iptu_cents, city: property.cidade, neighborhood: property.bairro } },
            tasks: tasks.first(20).map { |task| { id: task.id, title: task.title, kind: task.kind_label, priority: task.priority_label, due_at: task.due_at&.iso8601 } }
          }
        end

        private

        def catalog_params
          lists = %i[category quick development owner status city neighborhood situation keys amenities exchange_type]
          ranges = ::BrowserExtension::PropertyCatalog::RANGES.keys.flat_map { |key| [key, "#{key}_min", "#{key}_max"] }
          params.permit(:q, :purpose, :facet, :order, :direction, :reference, :address, :number,
            :promotion, :exchange, :installments, :rental_management, :min_price, :max_price,
            *ranges, *lists, lists.index_with { [] })
        end

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
