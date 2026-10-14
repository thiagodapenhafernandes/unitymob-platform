module Automation
  class ScheduleCalculator
    DEFAULT_BUSINESS_START = "09:00"
    DEFAULT_BUSINESS_END = "18:00"

    CLOCK_FORMAT = /\A(?:[01]\d|2[0-3]):[0-5]\d\z/

    def self.validation_messages(config)
      config = (config || {}).with_indifferent_access
      return [] unless %w[business_duration next_business_window].include?(config[:mode].to_s)

      start = config[:business_start].presence || DEFAULT_BUSINESS_START
      finish = config[:business_end].presence || DEFAULT_BUSINESS_END
      return ["tem janela comercial com horario invalido"] unless CLOCK_FORMAT.match?(start.to_s) && CLOCK_FORMAT.match?(finish.to_s)
      return ["tem janela comercial com inicio igual ou posterior ao fim"] unless start.to_s < finish.to_s

      []
    end

    def self.recurring_validation_messages(config)
      config = config.with_indifferent_access
      frequency = config[:schedule_frequency].presence || "every_n_minutes"
      errors = []
      errors << "tem rotina agendada com frequencia invalida" unless %w[every_n_minutes daily weekly monthly].include?(frequency.to_s)
      if frequency == "every_n_minutes"
        errors << "tem rotina agendada sem intervalo inteiro de ao menos um minuto" unless config[:interval].to_s.match?(/\A[1-9]\d*\z/)
      else
        errors << "tem rotina agendada com horario invalido" unless CLOCK_FORMAT.match?((config[:time_of_day].presence || "09:00").to_s)
      end
      errors << "tem rotina agendada mensal sem dia valido" if frequency == "monthly" && !config[:month_day].to_s.match?(/\A(?:[1-9]|[12]\d|3[01])\z/)
      errors << "tem rotina agendada semanal com dia invalido" if frequency == "weekly" && Array(config[:weekdays]).any? { |day| !day.to_s.match?(/\A[0-6]\z/) }
      errors
    end

    def self.wait_until(config, now: Time.current)
      new(config, now: now).wait_until
    end

    def self.recurring_bucket(config, now: Time.current)
      new(config, now: now).recurring_bucket
    end

    def self.recurring_due?(config, now: Time.current, lookback: 2.minutes)
      new(config, now: now).recurring_due?(lookback: lookback)
    end

    def initialize(config, now: Time.current)
      @config = (config || {}).with_indifferent_access
      @now = now
    end

    def wait_until
      errors = self.class.validation_messages(@config)
      raise ArgumentError, errors.join(", ") if errors.any?

      case @config[:mode].to_s
      when "datetime"
        parse_time(@config[:run_at]) || @now
      when "business_duration"
        add_business_duration(duration_seconds)
      when "next_business_window"
        next_business_open(@now)
      else
        @now + duration_seconds
      end
    end

    def recurring_due?(lookback: 2.minutes)
      validate_recurring!
      case recurring_frequency
      when "daily", "weekly", "monthly"
        run_at = recurring_run_at
        run_at && run_at <= @now && run_at > (@now - lookback)
      else
        true
      end
    end

    def recurring_bucket
      validate_recurring!
      case recurring_frequency
      when "daily"
        @now.strftime("%Y%m%d")
      when "weekly"
        "#{@now.strftime('%G%V')}:#{@now.wday}"
      when "monthly"
        @now.strftime("%Y%m")
      else
        seconds = [@config[:interval].to_i, 1].max.minutes.to_i
        bucket = (@now.to_i / seconds) * seconds
        Time.zone.at(bucket).strftime("%Y%m%d%H%M")
      end
    end

    private

    def validate_recurring!
      errors = self.class.recurring_validation_messages(@config)
      raise ArgumentError, errors.join(", ") if errors.any?
    end

    def recurring_frequency
      @config[:schedule_frequency].presence || "every_n_minutes"
    end

    def recurring_run_at
      hour, minute = parse_hour_minute(@config[:time_of_day].presence || "09:00")

      case recurring_frequency
      when "daily"
        @now.change(hour: hour, min: minute, sec: 0)
      when "weekly"
        return unless selected_weekday?

        @now.change(hour: hour, min: minute, sec: 0)
      when "monthly"
        day = [[@config[:month_day].to_i, 1].max, @now.end_of_month.day].min
        return unless @now.day == day

        @now.change(hour: hour, min: minute, sec: 0)
      end
    end

    def selected_weekday?
      weekdays = Array(@config[:weekdays]).map(&:to_s).reject(&:blank?)
      weekdays.empty? || weekdays.include?(@now.wday.to_s)
    end

    def duration_seconds
      amount = @config[:amount].to_i
      amount = 1 unless amount.positive?

      case @config[:unit].to_s
      when "minutes" then amount.minutes
      when "hours" then amount.hours
      else amount.days
      end
    end

    def add_business_duration(seconds)
      remaining = seconds.to_i
      cursor = next_business_open(@now)

      while remaining.positive?
        close_at = business_close_for(cursor)
        available = [close_at - cursor, 0].max

        if remaining <= available
          return cursor + remaining
        end

        remaining -= available.to_i
        cursor = next_business_open(close_at + 1.minute)
      end

      cursor
    end

    def next_business_open(time)
      cursor = time

      loop do
        if skip_weekend? && weekend?(cursor)
          cursor = cursor.next_day.beginning_of_day
          next
        end
        open_at = business_open_for(cursor)
        close_at = business_close_for(cursor)

        return open_at if cursor < open_at
        return cursor if cursor < close_at

        cursor = (cursor + 1.day).beginning_of_day
      end
    end

    def business_open_for(time)
      hour, minute = parse_hour_minute(@config[:business_start].presence || DEFAULT_BUSINESS_START)
      time.change(hour: hour, min: minute, sec: 0)
    end

    def business_close_for(time)
      hour, minute = parse_hour_minute(@config[:business_end].presence || DEFAULT_BUSINESS_END)
      time.change(hour: hour, min: minute, sec: 0)
    end

    def parse_hour_minute(value)
      hour, minute = value.to_s.split(":").map(&:to_i)
      [[hour || 0, 0].max, [minute || 0, 0].max]
    end

    def parse_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def skip_weekend?
      ActiveModel::Type::Boolean.new.cast(@config.fetch(:skip_weekends, true))
    end

    def weekend?(time)
      time.saturday? || time.sunday?
    end
  end
end
