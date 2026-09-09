module Api
  module V1
    module BrowserExtension
      class OperationsController < BaseController
        before_action :authorize_operation!
        rescue_from ActiveRecord::RecordInvalid, with: -> { render json: { error: "invalid_fields" }, status: :unprocessable_entity }
        rescue_from ActionController::ParameterMissing, ArgumentError, with: -> { render json: { error: "invalid_fields" }, status: :unprocessable_entity }

        def create_lead
          attrs = params.require(:lead).permit(:name, :phone, :email).to_h
          attrs["name"] = required_text(attrs["name"], 200)
          attrs["phone"] = confirmed_phone!
          attrs["email"] = attrs["email"].to_s.strip.presence
          raise ArgumentError if attrs["email"] && (attrs["email"].length > 254 || !attrs["email"].match?(URI::MailTo::EMAIL_REGEXP))

          persist_once(attrs) do
            pipeline = LeadPipeline.default_for(tenant: grant.tenant)
            stage = pipeline&.stages&.active&.detect { |item| item.name.to_s.parameterize(separator: "_") == "em_atendimento" }
            raise ArgumentError unless stage
            lead = grant.tenant.leads.create!(attrs.merge(admin_user: grant.admin_user, origin: "WhatsApp",
              other_information: {"creation_source" => "browser_extension"},
              lead_pipeline: pipeline, lead_pipeline_stage: stage, status: stage.name))
            lead.activities.create!(tenant: grant.tenant, kind: "created", metadata: actor.merge(origin: lead.origin, owner_id: grant.admin_user_id))
            { lead_id: lead.id }
          end
        end

        def create_note
          lead = confirmed_lead!
          body = required_text(params.require(:note).permit(:body)[:body], 5000)
          persist_once({ body: body }) do
            note = lead.activities.create!(tenant: grant.tenant, kind: "note",
              metadata: actor.merge(contact_kind: "nota", body: body))
            { lead_id: lead.id, note_id: note.id }
          end
        end

        def create_contact
          lead = confirmed_lead!
          attrs = params.require(:contact).permit(:body, :contact_kind, :contact_result).to_h
          body = required_text(attrs["body"], 5000)
          kind = attrs["contact_kind"]
          raise ArgumentError unless (LeadActivity::CONTACT_ATTEMPT_KINDS + ["nota"]).include?(kind)
          result = attrs["contact_result"].presence
          if LeadActivity::CONTACT_ATTEMPT_KINDS.include?(kind)
            raise ArgumentError unless LeadActivity::CONTACT_RESULT_LABELS.key?(result)
          else
            result = nil
          end
          metadata = {contact_kind: kind, contact_result: result, body: body}.compact
          persist_once(metadata) do
            activity = lead.activities.create!(tenant: grant.tenant, kind: "note", metadata: actor.merge(metadata))
            {lead_id: lead.id, note_id: activity.id}
          end
        end

        def create_task
          lead = confirmed_lead!
          attrs = params.require(:task).permit(:title, :kind, :due_at, :priority).to_h
          attrs["title"] = required_text(attrs["title"], 200)
          due_at = Time.iso8601(attrs["due_at"].to_s)
          raise ArgumentError unless Task::PRIORITIES.key?(attrs["priority"]) && Task::KINDS.key?(attrs["kind"])

          persist_once(attrs) do
            raise ArgumentError unless due_at > Time.current
            task = grant.tenant.tasks.create!(attrs.merge(due_at: due_at, lead: lead, admin_user: grant.admin_user,
              created_by: grant.admin_user, status: "pendente", source: "manual"))
            lead.activities.create!(tenant: grant.tenant, kind: "task_created",
              metadata: actor.merge(task_id: task.id, title: task.title, due_at: task.due_at))
            { lead_id: lead.id, task_id: task.id }
          end
        end

        def create_appointment
          lead = confirmed_lead!
          attrs = params.require(:appointment).permit(:title, :kind, :starts_at, :ends_at, :location).to_h
          attrs["title"] = required_text(attrs["title"], 200)
          starts_at = Time.iso8601(attrs["starts_at"].to_s)
          ends_at = Time.iso8601(attrs["ends_at"]) if attrs["ends_at"].present?
          raise ArgumentError unless Appointment::KINDS.key?(attrs["kind"]) && (!ends_at || ends_at > starts_at)
          raise ArgumentError if attrs["location"].to_s.length > 300
          persist_once(attrs) do
            raise ArgumentError unless starts_at > Time.current
            appointment = grant.tenant.appointments.create!(attrs.merge(starts_at: starts_at, ends_at: ends_at,
              lead: lead, admin_user: grant.admin_user, status: "agendado"))
            lead.activities.create!(tenant: grant.tenant, kind: "appointment_created",
              metadata: actor.merge(appointment_id: appointment.id, title: appointment.title, starts_at: appointment.starts_at, kind: appointment.kind))
            { lead_id: lead.id, appointment_id: appointment.id }
          end
        end

        def change_status
          lead = confirmed_lead!
          attrs = params.require(:status).permit(:stage_id, :expected_stage_id).to_h
          raise ArgumentError unless attrs["stage_id"].to_s.match?(/\A[1-9]\d*\z/) && attrs["expected_stage_id"].to_s.match?(/\A\d*\z/)
          persist_once(attrs) do
            lead.with_lock do
              if lead.lead_pipeline_stage_id.to_s != attrs["expected_stage_id"].to_s
                return render json: {error: "lead_changed"}, status: :conflict
              end
              stage = available_status_stages(lead).find { |candidate| candidate.id.to_s == attrs["stage_id"] }
              raise ArgumentError unless stage
              previous = lead.status
              lead.update!(lead_pipeline_stage: stage, status: stage.name)
              if previous != lead.status
                lead.activities.create!(tenant: grant.tenant, kind: "status_change", metadata: actor.merge(from: previous, to: lead.status))
              end
            end
            {lead_id: lead.id}
          end
        end

        def unlink_property
          lead = confirmed_lead!
          id = params.require(:property).permit(:id)[:id].to_s
          raise ArgumentError unless id.match?(/\A[1-9]\d*\z/)
          persist_once({id: id}) do
            lead.with_lock do
              raise ArgumentError if lead.property_id.to_s == id
              lead.property_interests.where(tenant_id: grant.tenant_id, habitation_id: id).destroy_all
            end
            {lead_id: lead.id}
          end
        end

        def link_properties
          lead = confirmed_lead!
          raw = params.require(:properties).permit(:ids)[:ids].to_s
          raise ArgumentError unless raw.length <= 1000 && raw.match?(/\A\d+(?:,\d+)*\z/)
          ids = raw.split(",").map(&:to_i).uniq.sort
          raise ArgumentError if ids.length > 20
          persist_once({ids: ids}) do
            properties = property_scope.where(id: ids).to_a
            raise ActiveRecord::RecordNotFound unless properties.length == ids.length
            lead.with_lock do
              properties.each { |property| lead.property_interests.find_or_create_by!(tenant: grant.tenant, habitation: property) }
            end
            {lead_id: lead.id}
          end
        end

        def set_labels
          lead = confirmed_lead!
          raw = params.require(:labels).permit(:ids)[:ids].to_s
          raise ArgumentError unless raw.length <= 2000 && raw.match?(/\A(?:\d+(?:,\d+)*)?\z/)
          ids = raw.split(",").map(&:to_i).uniq.sort
          own_labels = grant.admin_user.lead_labels.where(tenant_id: grant.tenant_id)
          raise ArgumentError unless own_labels.where(id: ids).count == ids.length
          persist_once({ ids: ids }) do
            lead.with_lock do
              lead.lead_labelings.where(tenant_id: grant.tenant_id, lead_label_id: own_labels.select(:id)).where.not(lead_label_id: ids).destroy_all
              ids.each { |id| lead.lead_labelings.find_or_create_by!(tenant: grant.tenant, lead_label_id: id) }
            end
            { lead_id: lead.id }
          end
        end

        private

        def authorize_operation!
          return render json: { error: "terms_required" }, status: :forbidden unless grant.terms_accepted?
          capability = { "create_lead" => :create_leads, "create_note" => :create_notes, "create_contact" => :create_notes, "create_task" => :create_tasks, "create_appointment" => :create_appointments, "set_labels" => :manage_labels, "link_properties" => :link_properties, "unlink_property" => :link_properties, "change_status" => :change_status }.fetch(action_name)
          render json: { error: "permission_denied" }, status: :forbidden unless grant.capabilities[capability]
        end

        def required_text(value, maximum)
          text = value.to_s.strip
          raise ArgumentError if text.empty? || text.length > maximum
          text
        end

        def confirmed_phone!
          raise ArgumentError unless params[:confirmed] == true
          phone = Phones::Normalizer.call(params[:contact_phone].to_s.first(40))
          raise ArgumentError unless phone
          phone
        end

        def confirmed_lead!
          lead = lead_scope.find(params[:id])
          phone = confirmed_phone!
          raise ArgumentError unless [lead.phone, lead.client_phone].filter_map { |value| Phones::Normalizer.call(value) }.include?(phone)
          lead
        end

        def actor
          { by: grant.admin_user.name, admin_user_id: grant.admin_user_id, source: "browser_extension" }
        end

        # A receipt and its records commit together; retrying after a timeout cannot duplicate them.
        def persist_once(attrs)
          key = params[:request_key].to_s
          raise ArgumentError unless key.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
          digest = BrowserExtensionGrant.digest([action_name, params[:id].to_s, confirmed_phone!, attrs.sort.to_h].to_json)
          result = nil
          grant.with_lock do
            return render json: { error: "unauthorized" }, status: :unauthorized unless grant.accessible?
            authorize_operation!
            return if performed?
            operation = grant.operations.find_by(request_key: key)
            if operation
              return render json: { error: "request_conflict" }, status: :conflict unless operation.request_digest == digest
              result = operation.result
            else
              result = yield
              grant.operations.create!(request_key: key, request_digest: digest, result: result)
            end
          end
          render json: result, status: :ok
        end
      end
    end
  end
end
