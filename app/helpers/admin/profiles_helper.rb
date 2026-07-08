module Admin::ProfilesHelper
  def profile_filter_label(profile)
    axis_label = profile.horizontal? ? "Horizontal" : "Vertical"
    anchor = profile.horizontal? ? " · #{profile.vertical_profile&.name || 'sem vínculo'}" : nil
    "#{profile.name} (#{axis_label}#{anchor})"
  end
end
