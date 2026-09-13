module Leads
  class PoolTimeline
    CONTEXTS = %w[pool shark_tank pocket_pool pool_renotify].freeze
    STARTS = %w[shark_tank_ready pocket_pool_ready].freeze
    KINDS = (STARTS + %w[notification_sent notification_failed notification_skipped accepted distributed assigned_directly]).freeze

    def self.for(lead, viewer:)
      return [] unless viewer&.tenant_owner? && viewer.tenant_id == lead.tenant_id

      activities = lead.activities.where(kind: KINDS).order(:created_at, :id).to_a
      return [] unless activities.any? { |event| STARTS.include?(event.kind) || CONTEXTS.include?(event.meta("notification_context")) }

      pushes = PushDeliveryEvent.where(lead_id: lead.id, admin_user_id: lead.tenant.admin_users.select(:id), event_type: "device_received").order(:created_at).to_a
      rule_ids = activities.filter_map { |event| event.meta("rule_id") }.push(lead.distribution_rule_id).compact
      memberships = lead.tenant.distribution_rules.where(id: rule_ids).to_h { |rule| [rule.id.to_s, rule.pool_timeline_participants] }
      new(activities, pushes, memberships: memberships, default_rule_id: lead.distribution_rule_id).cycles
    end

    def initialize(activities, pushes, memberships: {}, default_rule_id: nil)
      @activities, @pushes = activities, pushes
      @memberships, @default_rule_id = memberships, default_rule_id
    end

    def cycles
      groups = []
      current = nil
      @activities.each do |event|
        if STARTS.include?(event.kind)
          current[:end] = event.created_at if current
          current = { id: event.id, start: event.created_at, notifications: [], accepted: nil, participants: event.meta("participants") || @memberships[(event.meta("rule_id") || @default_rule_id).to_s] || [] }
          groups << current
        elsif %w[distributed assigned_directly].include?(event.kind)
          current[:end] = event.created_at if current
          current = nil
        elsif event.kind.start_with?("notification_") && CONTEXTS.include?(event.meta("notification_context"))
          unless current
            current = { id: event.id, start: event.created_at, notifications: [], accepted: nil, participants: event.meta("participants") || @memberships[(event.meta("rule_id") || @default_rule_id).to_s] || [] }
            groups << current
          end
          current[:notifications] << event
        elsif event.kind == "accepted" && ActiveModel::Type::Boolean.new.cast(event.meta("shark_tank"))
          current[:accepted] ||= event if current
        end
      end
      groups.each_with_index.map { |group, index| build_cycle(group, groups[index + 1]&.dig(:start)) }.reverse
    end

    private

    def build_cycle(group, next_start)
      next_start = [group[:end], next_start].compact.min
      rows = group[:notifications].group_by { |event| event.meta("admin_user_id") }.filter_map do |id, events|
        next if id.blank?
        name = events.filter_map { |event| event.meta("admin_user_name").presence }.last || "Corretor ##{id}"
        points = events.flat_map do |event|
          channel = event.meta("channel")
          next [] unless %w[whatsapp push email].include?(channel)
          sent = event.kind == "notification_sent"
          result = [{ channel: channel, state: sent ? "Enviado" : (event.kind == "notification_failed" ? "Falhou" : "Não enviado"), at: event.created_at }]
          if sent && channel == "whatsapp"
            { "whatsapp_delivered_at" => "Recebeu", "whatsapp_read_at" => "Leu" }.each do |key, state|
              at = parse_time(event.meta(key))
              result << { channel: channel, state: state, at: at } if at
            end
          end
          result
        end
        push_sent = events.select { |event| event.kind == "notification_sent" && event.meta("channel") == "push" }.map(&:created_at).min
        if push_sent
          received = @pushes.find { |event| event.admin_user_id.to_s == id.to_s && event.created_at >= push_sent && (!next_start || event.created_at < next_start) }
          points << { channel: "push", state: "Recebeu", at: received.created_at } if received
        end
        { id: id, name: name, points: points.group_by { |point| [point[:channel], point[:state]] }.values.map { |items| items.min_by { |point| point[:at] } } }
      end

      group[:participants].each do |participant|
        participant = participant.with_indifferent_access
        next if rows.any? { |row| row[:id].to_s == participant[:id].to_s }
        rows << { id: participant[:id], name: participant[:name], points: [] }
      end
      rows.sort_by! { |row| [row[:name].to_s.downcase, row[:id].to_s] }

      accepted = group[:accepted]
      if accepted
        matches = rows.select { |row| row[:name] == accepted.meta("by") }
        winner = rows.find { |row| row[:id].to_s == accepted.meta("admin_user_id").to_s } || (matches.one? ? matches.first : nil)
        unless winner
          winner = { id: nil, name: accepted.meta("by").presence || "Atendimento registrado", points: [] }
          rows << winner
        end
        winner[:points] << { channel: "attendance", state: "Atendeu", at: accepted.created_at }
      end
      points = rows.flat_map { |row| row[:points] }
      start = ([group[:start]] + points.map { |point| point[:at] }).min
      finish = points.map { |point| point[:at] }.max || start
      {
        id: group[:id], start: start, duration: [finish - start, 1].max, rows: rows,
        notified: rows.count { |row| row[:points].any? { |point| point[:state] == "Enviado" } },
        delivered: rows.count { |row| row[:points].any? { |point| point[:state] == "Recebeu" } },
        read: rows.count { |row| row[:points].any? { |point| point[:state] == "Leu" } },
        accepted: accepted ? 1 : 0, response_seconds: accepted ? (accepted.created_at - start).round : nil
      }
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) if value.present?
    rescue ArgumentError, TypeError
      nil
    end
  end
end
