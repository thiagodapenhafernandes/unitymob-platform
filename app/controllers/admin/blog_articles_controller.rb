require "aws-sdk-s3"

class Admin::BlogArticlesController < Admin::BaseController
  include BlogArticlePresentation
  before_action -> { check_permission!(:manage, :marketing) }
  before_action :set_article, only: %i[edit update destroy preview]
  before_action :load_categories, only: %i[new create edit update]

  def index
    @categories = current_tenant.blog_categories.order(:name)
    scope = current_tenant.blog_articles.matching(params[:q])
    scope = scope.where(status: params[:status]) if params[:status].in?(BlogArticle.statuses.keys)
    if params[:category_id].present?
      category = @categories.find(params[:category_id])
      scope = scope.joins(:blog_categorizations).where(blog_categorizations: { blog_category_id: category.id })
    end
    @articles = scope.order(Arel.sql("published_at DESC NULLS LAST"), id: :desc).with_attached_cover.includes(:blog_categories).paginate(page: params[:page], per_page: 20)
  end

  def new
    @article = current_tenant.blog_articles.new
  end

  def create
    @article = current_tenant.blog_articles.new
    persist_article(:new)
  end

  def edit; end

  def update
    persist_article(:edit)
  end

  def destroy
    @article.destroy!
    redirect_to admin_blog_articles_path, notice: "Artigo excluído.", status: :see_other
  end

  def preview
    @public_tenant = current_tenant
    load_public_site_settings
    @blog_article = @article
    prepare_blog_article
    render "blog/show", layout: "application"
  end

  private

  def set_article
    @article = current_tenant.blog_articles.with_rich_text_content_and_embeds.with_attached_cover.includes(:blog_categories).find(params[:id])
  end

  def load_categories
    @categories = current_tenant.blog_categories.order(:name)
  end

  def persist_article(template)
    attributes = params.require(:blog_article).permit(:title, :slug, :content, :excerpt, :status, :published_at, :cover_alt, :meta_title, :meta_description, :cover, blog_category_ids: [])
    ids = Array(attributes.delete(:blog_category_ids)).reject(&:blank?).map(&:to_i).uniq
    categories = current_tenant.blog_categories.where(id: ids).to_a
    raise ActiveRecord::RecordNotFound unless categories.size == ids.size

    cover = attributes.delete(:cover)
    @article.assign_attributes(attributes)
    if cover.present?
      blob = cover.is_a?(ActionDispatch::Http::UploadedFile) ? Blog::Storage.upload!(cover, tenant: current_tenant, images_only: true) : ActiveStorage::Blob.find_signed!(cover)
      unless Blog::Storage.owned?(blob, current_tenant.id) && Blog::Storage::IMAGE_TYPES.include?(blob.content_type)
        raise ArgumentError, "A capa deve ser uma imagem desta conta."
      end
      @article.cover = blob
    end
    # Upload outside the transaction: a rejected form must retain the blob's ownership record.
    BlogArticle.transaction do
      @article.blog_categories = categories
      if @article.save
        redirect_to edit_admin_blog_article_path(@article), notice: "Artigo salvo.", status: :see_other
      else
        render template, status: :unprocessable_entity
        raise ActiveRecord::Rollback
      end
    end
  rescue ArgumentError => e
    @article.errors.add(:base, e.message)
    render template, status: :unprocessable_entity
  rescue Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError
    @article.errors.add(:base, "Não foi possível enviar ao Spaces. Tente novamente.")
    render template, status: :service_unavailable
  end
end
