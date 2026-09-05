module SlaHelper
  def sla_duration(seconds)
    return 'Sem medição' if seconds.nil?
    seconds = [seconds.to_i, 0].max
    parts = []
    parts << "#{seconds / 3600}h" if seconds >= 3600
    parts << "#{(seconds % 3600) / 60}min" if seconds >= 60
    parts << "#{seconds % 60}s" if seconds % 60 > 0 || parts.empty?
    parts.join(' ')
  end

end
