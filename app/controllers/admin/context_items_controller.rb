class Admin::ContextItemsController < Admin::BaseController
  def destroy
    forget_admin_context_item(params[:id])
    redirect_back fallback_location: admin_root_path
  end

  def clear
    clear_admin_context_items
    redirect_back fallback_location: admin_root_path
  end
end
