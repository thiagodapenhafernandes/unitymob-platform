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
            lead = grant.tenant.leads.create!(attrs.merge(admin_user: grant.admin_user, origin: "Cadastro manual",
              lead_pipeline: pipeline, lead_pipeline_stage: pipeline&.default_stage,
              status: pipeline&.default_stage&.name || Lead.status_value(:novo, tenant: grant.tenant)))
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

        private

        def authorize_operation!
          return render json: { error: "terms_required" }, status: :forbidden unless grant.terms_accepted?
          capability = { "create_lead" => :create_leads, "create_note" => :create_notes, "create_task" => :create_tasks }.fetch(action_name)
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
