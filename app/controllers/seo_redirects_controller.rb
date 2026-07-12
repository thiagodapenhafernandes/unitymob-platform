class SeoRedirectsController < ApplicationController
  def show
    redirect_record = public_tenant.seo_redirects.active.find_by(from_path: redirect_lookup_path) ||
                      public_tenant.seo_redirects.active.find_by(from_path: request.path)

    raise ActionController::RoutingError, "Not Found" if redirect_record.blank?

    redirect_record.register_hit!
    redirect_to redirect_record.to_path, status: redirect_record.status_code, allow_other_host: true
  end

  private

  def redirect_lookup_path
    query = request.query_string.present? ? "?#{request.query_string}" : ""
    "#{request.path}#{query}"
  end
end
