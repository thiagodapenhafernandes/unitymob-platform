module RentalAvailabilityHelper
  def rental_availability_month(value)
    text = value.to_s
    return Date.current.beginning_of_month unless text.match?(/\A\d{4}-\d{2}\z/)

    Date.strptime(text, "%Y-%m").beginning_of_month
  rescue Date::Error
    Date.current.beginning_of_month
  end

  def rental_availability_days(month, blocks)
    blocked = blocks.flat_map do |block|
      ([block.starts_on, month].max..[block.ends_on, month.end_of_month].min).to_a
    end.to_set
    (month.beginning_of_week(:sunday)..month.end_of_month.end_of_week(:sunday)).map do |day|
      [day, blocked.include?(day)]
    end.each_slice(7)
  end
end
