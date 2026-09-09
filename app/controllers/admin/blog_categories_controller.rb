class Admin::BlogCategoriesController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }

  def create
    category = current_tenant.blog_categories.new(params.require(:blog_category).permit(:name))
    if category.save
      render json: { id: category.id, name: category.name, html: render_to_string(partial: "admin/shared/ui/filter_check", formats: [:html], locals: { name: "blog_article[blog_category_ids][]", value: category.id, checked: true, label: category.name, id: "blog-category-#{category.id}", class_name: nil }) }, status: :created
    else
      render json: { error: category.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end
end
