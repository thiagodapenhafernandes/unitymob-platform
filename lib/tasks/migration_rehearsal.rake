# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "shellwords"

module MigrationRehearsal
  module_function

  EXPORT_VERSION = 1
  DEFAULT_DIR = Rails.root.join("tmp", "migration_rehearsal")
  DEFAULT_REMOTE = "salute@143.110.138.67"
  DEFAULT_REMOTE_ENV = "/home/salute/deploy/shared/.env"
  DEFAULT_SYSTEM_ADMIN_EMAIL = "admin@unitymob.com.br"
  DEFAULT_LOCAL_ADMIN_PASSWORD = "t%$T75431311"
  DWV_CANONICAL_BASE_URL = "https://agencies.dwvapp.com.br"

  def truthy?(value)
    value.to_s.strip.downcase.in?(%w[1 true yes y on])
  end

  def ensure_development!
    return if Rails.env.development?

    abort "[migration_rehearsal] bloqueado fora de development."
  end

  def timestamp
    Time.current.strftime("%Y%m%d%H%M%S")
  end

  def default_export_path
    DEFAULT_DIR.join("hierarchy-#{timestamp}.json")
  end

  def default_dump_path
    DEFAULT_DIR.join("production-#{timestamp}.dump")
  end

  def default_local_backup_path
    DEFAULT_DIR.join("local-before-restore-#{timestamp}.dump")
  end

  def write_json!(path, payload)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(payload))
    path
  end

  def read_json!(path)
    JSON.parse(File.read(path))
  rescue Errno::ENOENT
    abort "[migration_rehearsal] arquivo não encontrado: #{path}"
  rescue JSON::ParserError => e
    abort "[migration_rehearsal] JSON inválido em #{path}: #{e.message}"
  end

  def tenant_ref(tenant)
    return nil if tenant.blank?

    {
      "id" => tenant.id,
      "slug" => tenant.try(:slug),
      "name" => tenant.try(:name)
    }
  end

  def tenant_key(tenant_or_ref)
    return nil if tenant_or_ref.blank?

    slug = tenant_or_ref.respond_to?(:slug) ? tenant_or_ref.slug : tenant_or_ref["slug"]
    name = tenant_or_ref.respond_to?(:name) ? tenant_or_ref.name : tenant_or_ref["name"]
    slug.presence || name.presence
  end

  def profile_ref(profile)
    return nil if profile.blank?

    {
      "tenant" => tenant_ref(profile.tenant),
      "axis" => profile.axis,
      "key" => profile.key,
      "name" => profile.name,
      "position" => profile.position,
      "vertical_profile_key" => profile.vertical_profile&.key,
      "vertical_profile_name" => profile.vertical_profile&.name
    }
  end

  def user_ref(user)
    return nil if user.blank?

    {
      "tenant" => tenant_ref(user.tenant),
      "email" => user.email,
      "contact_email" => user.try(:contact_email),
      "name" => user.name
    }
  end

  def normalized_email(value)
    value.to_s.strip.downcase.presence
  end

  def model_columns(model)
    model.column_names
  end

  def export_admin_passwords?
    truthy?(ENV.fetch("EXPORT_ADMIN_PASSWORDS", "false"))
  end

  def import_admin_passwords?
    truthy?(ENV.fetch("IMPORT_ADMIN_PASSWORDS", "false"))
  end

  def export_profile(profile)
    profile.attributes.slice(
      "name", "permissions", "active", "key", "axis", "position", "locked"
    ).merge(
      "tenant" => tenant_ref(profile.tenant),
      "vertical_profile" => profile_ref(profile.vertical_profile)
    )
  end

  def export_admin_user(user)
    safe_columns = %w[
      email name role vista_id creci phone biography birth_date city
      acting_type field_agent_enabled active require_ip_allowlist require_trusted_device
      display_on_site vista_agenciador source_created_on source_departed_on source_photo_path
      nationality gender marital_status address_type street number complement neighborhood
      secondary_phone team_code capture_goal rental_capture_goal sales_goal_cents
      hierarchy_position super_admin leads_view_mode contact_email
    ] & model_columns(AdminUser)

    attrs = user.attributes.slice(*safe_columns)
    attrs["encrypted_password"] = user.encrypted_password if export_admin_passwords? && model_columns(AdminUser).include?("encrypted_password")

    attrs.merge(
      "tenant" => tenant_ref(user.tenant),
      "profile" => profile_ref(user.profile),
      "horizontal_profile" => profile_ref(user.horizontal_profile),
      "manager" => user_ref(user.manager),
      "rentals_manager" => user_ref(user.try(:rentals_manager)),
      "primary_admin_user" => user_ref(user.try(:primary_admin_user))
    )
  end

  def export_account_membership(membership)
    membership.attributes.except(
      "id", "tenant_id", "profile_id", "horizontal_profile_id", "manager_id",
      "rentals_manager_id", "primary_admin_user_id", "member_admin_user_id",
      "invited_by_id", "revoked_by_id"
    ).merge(
      "tenant" => tenant_ref(membership.tenant),
      "profile" => profile_ref(membership.profile),
      "horizontal_profile" => profile_ref(membership.horizontal_profile),
      "manager" => user_ref(membership.manager),
      "rentals_manager" => user_ref(membership.rentals_manager),
      "primary_admin_user" => user_ref(membership.primary_admin_user),
      "member_admin_user" => user_ref(membership.member_admin_user),
      "invited_by" => user_ref(membership.invited_by),
      "revoked_by" => user_ref(membership.revoked_by)
    )
  end

  def export_distribution_rule(rule)
    rule.attributes.except("id", "tenant_id").merge(
      "tenant" => tenant_ref(rule.tenant),
      "agents" => rule.distribution_rule_agents.includes(:admin_user).order(:position, :id).map do |agent|
        agent.attributes.except("id", "distribution_rule_id", "admin_user_id", "tenant_id").merge(
          "admin_user" => user_ref(agent.admin_user)
        )
      end
    )
  end

  def export_payload
    tenants = Tenant.order(:id).to_a
    {
      "version" => EXPORT_VERSION,
      "exported_at" => Time.current.iso8601,
      "environment" => Rails.env,
      "database" => ActiveRecord::Base.connection.current_database,
      "tenants" => tenants.map { |tenant| tenant.attributes },
      "profiles" => Profile.includes(:tenant, :vertical_profile).order(:tenant_id, :axis, :position, :id).map { |profile| export_profile(profile) },
      "admin_users" => AdminUser.includes(:tenant, :profile, :horizontal_profile, :manager).order(:tenant_id, :id).map { |user| export_admin_user(user) },
      "account_memberships" => defined?(AccountMembership) ? AccountMembership.includes(:tenant, :profile, :horizontal_profile, :manager, :rentals_manager, :primary_admin_user, :member_admin_user, :invited_by, :revoked_by).order(:tenant_id, :id).map { |membership| export_account_membership(membership) } : [],
      "distribution_rules" => []
    }
  end

  def find_tenant(ref)
    return nil if ref.blank?

    slug = ref["slug"].to_s.strip
    name = ref["name"].to_s.strip
    tenant = Tenant.find_by(slug: slug) if slug.present? && Tenant.column_names.include?("slug")
    tenant ||= Tenant.find_by(name: name) if name.present? && Tenant.column_names.include?("name")
    tenant
  end

  def ensure_tenant!(attrs)
    tenant = find_tenant(attrs) || Tenant.new
    assignable = attrs.slice(*Tenant.column_names).except("id", "created_at", "updated_at")
    tenant.assign_attributes(assignable)
    tenant.save!(validate: false)
    tenant
  end

  def profile_lookup_key(ref)
    return nil if ref.blank?

    [
      tenant_key(ref["tenant"]),
      ref["axis"].presence || "vertical",
      ref["key"].presence || ref["name"].to_s,
      ref["vertical_profile_key"].presence || ref["vertical_profile_name"].to_s
    ].join("::")
  end

  def find_profile(ref, profile_map = {})
    return nil if ref.blank?

    profile_map[profile_lookup_key(ref)] ||
      begin
        tenant = find_tenant(ref["tenant"])
        if tenant
          scope = Profile.where(tenant_id: tenant.id, axis: ref["axis"].presence || "vertical")
          if ref["key"].present?
            scope.find_by(key: ref["key"])
          elsif ref["axis"] == "vertical"
            scope.find_by(name: ref["name"], position: ref["position"])
          else
            vertical = find_profile({
              "tenant" => ref["tenant"],
              "axis" => "vertical",
              "key" => ref["vertical_profile_key"],
              "name" => ref["vertical_profile_name"]
            }, profile_map)
            scope.find_by(name: ref["name"], vertical_profile_id: vertical&.id) ||
              Profile.where(tenant_id: tenant.id, axis: "vertical", name: ref["name"]).first
          end
        end
      end
  end

  def profile_referenced_as_anchor?(attrs, payload)
    key = profile_lookup_key(attrs)
    payload.fetch("profiles", []).any? { |profile_attrs| profile_lookup_key(profile_attrs["vertical_profile"]) == key }
  end

  def effective_profile_axis(attrs, payload)
    return attrs["axis"] unless attrs["axis"] == "horizontal"

    # Backups feitos antes da governança atual podem conter cadeia horizontal
    # (horizontal -> horizontal -> vertical). A estrutura nova aceita só
    # horizontal ancorado diretamente em vertical, então o nó intermediário vira
    # vertical durante o ensaio de migração.
    profile_referenced_as_anchor?(attrs, payload) ? "vertical" : "horizontal"
  end

  def vertical_position_for(attrs, tenant)
    return attrs["position"] if attrs["position"].present?
    return Profile::INTERNAL_MANAGEMENT_PROFILE_POSITION if defined?(Profile::INTERNAL_MANAGEMENT_PROFILE_POSITION) && attrs["name"] == Profile::INTERNAL_MANAGEMENT_PROFILE_NAME

    used_positions = Profile.where(tenant_id: tenant.id, axis: "vertical").where.not(position: nil).pluck(:position).map(&:to_i)
    candidate = 500
    candidate += 100 while used_positions.include?(candidate) && candidate < 9_900
    candidate
  end

  def upsert_profiles!(payload)
    profile_map = {}

    payload.fetch("profiles", []).select { |attrs| effective_profile_axis(attrs, payload) == "vertical" }.each do |attrs|
      tenant = find_tenant(attrs["tenant"]) || ensure_tenant!(attrs["tenant"])
      profile = if attrs["key"].present?
                  Profile.where(tenant_id: tenant.id, axis: "vertical").find_by(key: attrs["key"])
                else
                  Profile.where(tenant_id: tenant.id, axis: "vertical").find_by(name: attrs["name"])
                end
      profile ||= Profile.new(tenant: tenant, axis: "vertical")
      profile.assign_attributes(attrs.slice("name", "permissions", "active", "key", "axis", "position", "locked"))
      profile.tenant = tenant
      profile.axis = "vertical"
      profile.vertical_profile = nil
      profile.position = vertical_position_for(attrs, tenant)
      profile.save!(validate: false)
      profile_map[profile_lookup_key(profile_ref(profile))] = profile
      profile_map[profile_lookup_key(attrs)] = profile
    end

    payload.fetch("profiles", []).select { |attrs| effective_profile_axis(attrs, payload) == "horizontal" }.each do |attrs|
      tenant = find_tenant(attrs["tenant"]) || ensure_tenant!(attrs["tenant"])
      vertical = find_profile(attrs["vertical_profile"], profile_map)
      profile = Profile.where(tenant_id: tenant.id, axis: "horizontal", name: attrs["name"], vertical_profile_id: vertical&.id).first
      profile ||= Profile.new(tenant: tenant, axis: "horizontal")
      profile.assign_attributes(attrs.slice("name", "permissions", "active", "key", "axis", "locked"))
      profile.tenant = tenant
      profile.vertical_profile = vertical
      profile.position = nil
      profile.save!(validate: false)
      profile_map[profile_lookup_key(profile_ref(profile))] = profile
    end

    profile_map
  end

  def find_user(ref)
    return nil if ref.blank?

    tenant = find_tenant(ref["tenant"])
    emails = [normalized_email(ref["email"]), normalized_email(ref["contact_email"])].compact.uniq
    return nil if emails.blank?

    scope = tenant ? AdminUser.where(tenant_id: tenant.id) : AdminUser.all
    scope.where("lower(email) IN (:emails) OR lower(contact_email) IN (:emails)", emails: emails).first
  rescue ActiveRecord::StatementInvalid
    scope.where("lower(email) IN (?)", emails).first
  end

  def upsert_admin_users!(payload, profile_map)
    user_map = {}
    payload.fetch("admin_users", []).each do |attrs|
      system_admin = attrs["super_admin"] == true
      tenant = system_admin ? nil : (find_tenant(attrs["tenant"]) || ensure_tenant!(attrs["tenant"]))
      user = find_user(attrs) || AdminUser.new
      profile = find_profile(attrs["profile"], profile_map)
      horizontal_profile = find_profile(attrs["horizontal_profile"], profile_map)

      assignable = attrs.slice(*AdminUser.column_names).except(
        "id", "created_at", "updated_at", "tenant_id", "profile_id", "horizontal_profile_id",
        "manager_id", "rentals_manager_id", "primary_admin_user_id", "reset_password_token",
        "reset_password_sent_at", "remember_created_at", "last_login_at", "encrypted_password"
      )
      assignable["encrypted_password"] = attrs["encrypted_password"] if import_admin_passwords? && attrs["encrypted_password"].present?
      user.assign_attributes(assignable)
      user.tenant = system_admin ? nil : tenant
      user.profile = system_admin ? nil : profile
      user.horizontal_profile = system_admin ? nil : horizontal_profile
      user.manager = nil
      user.rentals_manager = nil if user.respond_to?(:rentals_manager=)
      user.primary_admin_user = nil if user.respond_to?(:primary_admin_user=)
      user.encrypted_password = Devise::Encryptor.digest(AdminUser, SecureRandom.hex(24)) if user.encrypted_password.blank?
      user.save!(validate: false)
      user_map[[tenant_key(attrs["tenant"]), normalized_email(attrs["email"])]] = user
      user_map[[tenant_key(attrs["tenant"]), normalized_email(attrs["contact_email"])]] = user if attrs["contact_email"].present?
    end

    payload.fetch("admin_users", []).each do |attrs|
      user = find_user(attrs)
      next unless user

      updates = {}
      manager = find_user(attrs["manager"])
      rentals_manager = find_user(attrs["rentals_manager"])
      primary = find_user(attrs["primary_admin_user"])
      updates[:manager_id] = manager&.id if AdminUser.column_names.include?("manager_id")
      updates[:rentals_manager_id] = rentals_manager&.id if AdminUser.column_names.include?("rentals_manager_id")
      updates[:primary_admin_user_id] = primary&.id if AdminUser.column_names.include?("primary_admin_user_id")
      user.update_columns(updates.merge(updated_at: Time.current)) if updates.any?
    end

    user_map
  end

  def upsert_distribution_rules!(payload)
    return unless defined?(DistributionRule)

    payload.fetch("distribution_rules", []).each do |attrs|
      tenant = find_tenant(attrs["tenant"])
      next unless tenant

      rule = DistributionRule.where(tenant_id: tenant.id, name: attrs["name"]).first || DistributionRule.new(tenant: tenant)
      assignable = attrs.slice(*DistributionRule.column_names).except("id", "tenant_id", "created_at", "updated_at")
      rule.assign_attributes(assignable)
      rule.tenant = tenant
      rule.save!(validate: false)

      next unless defined?(DistributionRuleAgent)

      keep_ids = []
      attrs.fetch("agents", []).each do |agent_attrs|
        admin_user = find_user(agent_attrs["admin_user"])
        next unless admin_user

        agent = rule.distribution_rule_agents.where(admin_user_id: admin_user.id).first || rule.distribution_rule_agents.build(admin_user: admin_user)
        agent.tenant_id = tenant.id if agent.respond_to?(:tenant_id=)
        agent.assign_attributes(agent_attrs.slice(*DistributionRuleAgent.column_names).except("id", "distribution_rule_id", "admin_user_id", "tenant_id", "created_at", "updated_at"))
        agent.save!(validate: false)
        keep_ids << agent.id
      end
      rule.distribution_rule_agents.where.not(id: keep_ids).delete_all if keep_ids.any?
    end
  end

  def import_hierarchy!(path:, apply:)
    payload = read_json!(path)
    puts "[migration_rehearsal:import_hierarchy] file=#{path} version=#{payload['version']} apply=#{apply}"
    puts "[migration_rehearsal:import_hierarchy] tenants=#{payload.fetch('tenants', []).size} profiles=#{payload.fetch('profiles', []).size} admin_users=#{payload.fetch('admin_users', []).size} account_memberships=#{payload.fetch('account_memberships', []).size} distribution_rules=#{payload.fetch('distribution_rules', []).size}"
    return unless apply

    ActiveRecord::Base.transaction do
      payload.fetch("tenants", []).each { |attrs| ensure_tenant!(attrs) }
      profile_map = upsert_profiles!(payload)
      upsert_admin_users!(payload, profile_map)
      upsert_distribution_rules!(payload)
    end
  end

  def local_admin_password
    ENV.fetch("LOCAL_ADMIN_PASSWORD", DEFAULT_LOCAL_ADMIN_PASSWORD)
  end

  def system_admin_email
    ENV.fetch("SYSTEM_ADMIN_EMAIL", DEFAULT_SYSTEM_ADMIN_EMAIL)
  end

  def reset_all_local_admin_passwords?
    truthy?(ENV.fetch("RESET_ALL_LOCAL_ADMIN_PASSWORDS", "true"))
  end

  def ensure_system_admin!(email: system_admin_email, password: local_admin_password, apply:)
    puts "[migration_rehearsal:ensure_system_admin] email=#{email} apply=#{apply}"
    return unless apply

    user = AdminUser.find_or_initialize_by(email: email)
    user.name = "Admin Unitymob" if user.respond_to?(:name=) && user.name.blank?
    user.role = "admin" if user.respond_to?(:role=)
    user.super_admin = true if user.respond_to?(:super_admin=)
    user.tenant = nil if user.respond_to?(:tenant=)
    user.profile = nil if user.respond_to?(:profile=)
    user.horizontal_profile = nil if user.respond_to?(:horizontal_profile=)
    user.manager = nil if user.respond_to?(:manager=)
    user.rentals_manager = nil if user.respond_to?(:rentals_manager=)
    user.primary_admin_user = nil if user.respond_to?(:primary_admin_user=)
    user.active = true if user.respond_to?(:active=)
    user.password = password
    user.password_confirmation = password
    user.save!
    puts "[migration_rehearsal:ensure_system_admin] id=#{user.id} super_admin=#{user.super_admin?} tenant_id=#{user.tenant_id.inspect}"
  end

  def reset_local_admin_passwords!(password: local_admin_password, apply:)
    total = AdminUser.count
    puts "[migration_rehearsal:reset_local_admin_passwords] admin_users=#{total} apply=#{apply}"
    return unless apply

    updated = 0
    AdminUser.find_each do |admin_user|
      admin_user.password = password
      admin_user.password_confirmation = password
      admin_user.save!(validate: false)
      updated += 1
    end
    puts "[migration_rehearsal:reset_local_admin_passwords] updated=#{updated}"
  end

  def repair_dwv_settings!(apply:)
    puts "[migration_rehearsal:repair_dwv_settings] base_url=#{DWV_CANONICAL_BASE_URL} apply=#{apply}"
    return unless apply

    Setting.set("dwv_base_url", DWV_CANONICAL_BASE_URL, "URL base da API DWV")

    return unless ActiveRecord::Base.connection.data_source_exists?("solid_queue_recurring_tasks")

    now = Time.current
    tasks = {
      "dwv_daily_sync" => [{"mode" => "full"}],
      "dwv_incremental_sync" => [{"mode" => "incremental"}]
    }

    tasks.each do |key, arguments|
      task = SolidQueue::RecurringTask.find_or_initialize_by(key: key)
      task.schedule = key == "dwv_daily_sync" ? "every day at 4:20am" : "every 5 minutes"
      task.class_name = "DwvSyncAllTenantsJob"
      task.command = nil
      task.arguments = arguments
      task.queue_name = "dwv"
      task.priority = nil
      task.static = true
      task.updated_at = now if task.persisted?
      task.save!(validate: false)
    end
  end

  def invoke_task!(name, env: {})
    abort "[migration_rehearsal] task não encontrado: #{name}" unless Rake::Task.task_defined?(name)

    old_env = env.each_with_object({}) { |(key, value), memo| memo[key] = ENV[key] }
    env.each { |key, value| ENV[key] = value }
    Rake::Task[name].reenable
    Rake::Task[name].invoke
  ensure
    old_env&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def repair_property_photos!(apply:)
    if Rake::Task.task_defined?("db_refresh:repair_property_photos")
      invoke_task!("db_refresh:repair_property_photos", env: { "APPLY" => apply ? "true" : "false" })
    else
      puts "[migration_rehearsal:repair_property_photos] task db_refresh:repair_property_photos indisponível"
    end
  end

  def post_restore_local!(hierarchy_file:, apply:)
    ensure_development!
    puts "[migration_rehearsal:post_restore_local] hierarchy_file=#{hierarchy_file} apply=#{apply}"
    import_hierarchy!(path: hierarchy_file, apply: apply) if hierarchy_file.present? && File.exist?(hierarchy_file)
    ensure_system_admin!(apply: apply)
    if reset_all_local_admin_passwords?
      reset_local_admin_passwords!(apply: apply)
    else
      puts "[migration_rehearsal:reset_local_admin_passwords] skipped RESET_ALL_LOCAL_ADMIN_PASSWORDS=false"
    end
    repair_dwv_settings!(apply: apply)
    repair_property_photos!(apply: apply)
  end

  def local_db_config
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    {
      database: ActiveRecord::Base.connection.current_database,
      host: config[:host] || "localhost",
      port: config[:port] || 5432,
      username: config[:username],
      password: config[:password].to_s
    }
  end

  def run_command!(command, env: {}, sensitive: false)
    display = sensitive ? command.first.to_s : command.shelljoin
    puts "[migration_rehearsal] running #{display}"
    status = nil
    Open3.popen2e(env, *command) do |_stdin, output, wait_thr|
      output.each { |line| puts line }
      status = wait_thr.value
    end
    abort "[migration_rehearsal] comando falhou: #{display}" unless status&.success?
  end

  def pull_production_dump!(path:)
    FileUtils.mkdir_p(File.dirname(path))
    remote = ENV.fetch("REMOTE_SSH", DEFAULT_REMOTE)
    remote_env = ENV.fetch("REMOTE_ENV", DEFAULT_REMOTE_ENV)
    remote_cmd = <<~SH.squish
      set -e;
      set -a;
      source #{remote_env.shellescape};
      set +a;
      PGPASSWORD="$DB_PASSWORD" pg_dump
        --format=custom
        --no-owner
        --no-acl
        --dbname="$DB_NAME"
        --username="$DB_USERNAME"
        --host="$DB_HOST"
        --port="${DB_PORT:-5432}"
    SH
    command = ["ssh", remote, remote_cmd]
    puts "[migration_rehearsal:pull_production_dump] remote=#{remote} output=#{path}"
    File.open(path, "wb") do |file|
      Open3.popen3(*command) do |_stdin, stdout, stderr, wait_thr|
        stdout.binmode
        IO.copy_stream(stdout, file)
        err = stderr.read
        warn err if err.present?
        abort "[migration_rehearsal:pull_production_dump] pg_dump remoto falhou" unless wait_thr.value.success?
      end
    end
    puts "[migration_rehearsal:pull_production_dump] dump_size=#{File.size(path)}"
    path
  end

  def backup_local_dump!(path:)
    ensure_development!
    FileUtils.mkdir_p(File.dirname(path))
    config = local_db_config
    env = {
      "PGHOST" => config[:host].to_s,
      "PGPORT" => config[:port].to_s,
      "PGUSER" => config[:username].to_s,
      "PGPASSWORD" => config[:password].to_s
    }
    run_command!(
      ["pg_dump", "--format=custom", "--no-owner", "--no-acl", "--dbname", config[:database].to_s, "--file", path.to_s],
      env: env,
      sensitive: true
    )
    puts "[migration_rehearsal:backup_local_dump] output=#{path} dump_size=#{File.size(path)}"
    path
  end

  def restore_local_dump!(path:, confirm:)
    ensure_development!
    config = local_db_config
    expected = config[:database]
    abort "[migration_rehearsal:restore_local_dump] confirme com CONFIRM=#{expected}" unless confirm == expected
    abort "[migration_rehearsal:restore_local_dump] dump não encontrado: #{path}" unless File.exist?(path)

    env = {
      "PGHOST" => config[:host].to_s,
      "PGPORT" => config[:port].to_s,
      "PGUSER" => config[:username].to_s,
      "PGPASSWORD" => config[:password].to_s
    }

    ActiveRecord::Base.connection.disconnect!
    run_command!(["dropdb", "--if-exists", "--force", expected], env: env, sensitive: true)
    run_command!(["createdb", expected], env: env, sensitive: true)
    run_command!(["pg_restore", "--no-owner", "--no-acl", "--dbname", expected, path.to_s], env: env, sensitive: true)
  end

  def validate_summary
    service_counts = if ActiveRecord::Base.connection.data_source_exists?("active_storage_blobs")
                       ActiveStorage::Blob.group(:service_name).order(:service_name).count
                     else
                       {}
                     end

    {
      database: ActiveRecord::Base.connection.current_database,
      tenants: Tenant.count,
      system_admins: AdminUser.where(super_admin: true).count,
      system_admin_emails: AdminUser.where(super_admin: true).order(:email).pluck(:email),
      profiles: Profile.count,
      admin_users: AdminUser.count,
      active_admin_users: AdminUser.where(active: true).count,
      distribution_rules: (defined?(DistributionRule) ? DistributionRule.count : nil),
      distribution_rule_agents: (defined?(DistributionRuleAgent) ? DistributionRuleAgent.count : nil),
      habitations: (defined?(Habitation) ? Habitation.count : nil),
      dwv_habitations: (defined?(Habitation) ? Habitation.where(imovel_dwv: "Sim").count : nil),
      leads: (defined?(Lead) ? Lead.count : nil),
      dwv_base_url: (defined?(Setting) ? Setting.get("dwv_base_url") : nil),
      dwv_incremental_recurring_class: (defined?(SolidQueue::RecurringTask) ? SolidQueue::RecurringTask.find_by(key: "dwv_incremental_sync")&.class_name : nil),
      photo_blobs_by_service: service_counts
    }
  end
end

namespace :migration_rehearsal do
  desc "Exporta hierarquia local em JSON para reimportar após restore do dump de produção"
  task export_hierarchy: :environment do
    MigrationRehearsal.ensure_development!

    path = ENV.fetch("OUTPUT", MigrationRehearsal.default_export_path.to_s)
    payload = MigrationRehearsal.export_payload
    MigrationRehearsal.write_json!(path, payload)
    puts "[migration_rehearsal:export_hierarchy] output=#{path}"
    puts "[migration_rehearsal:export_hierarchy] tenants=#{payload['tenants'].size} profiles=#{payload['profiles'].size} admin_users=#{payload['admin_users'].size} account_memberships=#{payload['account_memberships'].size} distribution_rules=#{payload['distribution_rules'].size}"
  end

  desc "Importa hierarquia local preservada por JSON. Use APPLY=true para gravar."
  task import_hierarchy: :environment do
    MigrationRehearsal.ensure_development!

    file = ENV["FILE"].presence || abort("[migration_rehearsal:import_hierarchy] informe FILE=tmp/migration_rehearsal/hierarchy-....json")
    apply = MigrationRehearsal.truthy?(ENV.fetch("APPLY", "false"))
    MigrationRehearsal.import_hierarchy!(path: file, apply: apply)
  end

  desc "Puxa dump custom format de produção via SSH para tmp/migration_rehearsal"
  task pull_production_dump: :environment do
    MigrationRehearsal.ensure_development!

    output = ENV.fetch("OUTPUT", MigrationRehearsal.default_dump_path.to_s)
    MigrationRehearsal.pull_production_dump!(path: output)
  end

  desc "DROP/CREATE do banco local e restaura dump. Requer CONFIRM=<database local>."
  task restore_local_dump: :environment do
    MigrationRehearsal.ensure_development!

    dump = ENV["DUMP"].presence || abort("[migration_rehearsal:restore_local_dump] informe DUMP=tmp/migration_rehearsal/production-....dump")
    MigrationRehearsal.restore_local_dump!(path: dump, confirm: ENV["CONFIRM"].to_s)
  end

  desc "Backup custom format do banco local antes de um ensaio destrutivo"
  task backup_local_dump: :environment do
    MigrationRehearsal.ensure_development!

    output = ENV.fetch("OUTPUT", MigrationRehearsal.default_local_backup_path.to_s)
    MigrationRehearsal.backup_local_dump!(path: output)
  end

  desc "Pós-restore local: importa hierarquia, garante Admin do Sistema, senhas, DWV e fotos. Use APPLY=true."
  task post_restore_local: :environment do
    MigrationRehearsal.ensure_development!

    hierarchy = ENV["HIERARCHY"].presence || ENV["FILE"].presence
    apply = MigrationRehearsal.truthy?(ENV.fetch("APPLY", "false"))
    MigrationRehearsal.post_restore_local!(hierarchy_file: hierarchy, apply: apply)
  end

  desc "Ensaio autônomo local: exporta preservados, puxa/restaura dump, migra, pós-restore e valida. Requer APPLY=true."
  task autonomous_local_cutover: :environment do
    MigrationRehearsal.ensure_development!
    abort "[migration_rehearsal:autonomous_local_cutover] use APPLY=true para executar o ensaio destrutivo local" unless MigrationRehearsal.truthy?(ENV.fetch("APPLY", "false"))

    hierarchy = ENV.fetch("HIERARCHY", MigrationRehearsal.default_export_path.to_s)
    local_backup = ENV.fetch("LOCAL_BACKUP", MigrationRehearsal.default_local_backup_path.to_s)
    dump = ENV["DUMP"].presence || MigrationRehearsal.default_dump_path.to_s
    db_name = ActiveRecord::Base.connection.current_database

    puts "[migration_rehearsal:autonomous_local_cutover] database=#{db_name}"
    puts "[migration_rehearsal:autonomous_local_cutover] hierarchy=#{hierarchy}"
    puts "[migration_rehearsal:autonomous_local_cutover] local_backup=#{local_backup}"
    puts "[migration_rehearsal:autonomous_local_cutover] production_dump=#{dump}"

    MigrationRehearsal.write_json!(hierarchy, MigrationRehearsal.export_payload)
    MigrationRehearsal.backup_local_dump!(path: local_backup)
    MigrationRehearsal.pull_production_dump!(path: dump) unless File.exist?(dump)
    MigrationRehearsal.restore_local_dump!(path: dump, confirm: db_name)

    Rake::Task["db:migrate"].reenable
    Rake::Task["db:migrate"].invoke

    MigrationRehearsal.post_restore_local!(hierarchy_file: hierarchy, apply: true)
    puts "[migration_rehearsal:autonomous_local_cutover] validate=#{MigrationRehearsal.validate_summary.to_json}"
  end

  desc "Resumo pós-restore/migração para validar dados e fotos"
  task validate: :environment do
    MigrationRehearsal.ensure_development!

    puts "[migration_rehearsal:validate] #{MigrationRehearsal.validate_summary.to_json}"
    if Rake::Task.task_defined?("db_refresh:property_photo_health")
      Rake::Task["db_refresh:property_photo_health"].reenable
      Rake::Task["db_refresh:property_photo_health"].invoke
    end
  end
end
