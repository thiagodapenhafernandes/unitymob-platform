module Admin
  class CaptacaoGoalsController < Admin::BaseController
    before_action -> { check_permission!(:view, :metas_captacao) }
    before_action -> { check_permission!(:manage, :metas_captacao) }, only: %i[new create edit update destroy]
    before_action :set_goal, only: [:edit, :update, :destroy]

    def index
      @goals = CaptacaoGoal.order(start_date: :desc, kind: :asc)
    end

    def new
      @goal = CaptacaoGoal.new(
        start_date: Date.current.beginning_of_month,
        end_date: Date.current.end_of_month,
        kind: :venda,
        target: 50
      )
    end

    def create
      @goal = CaptacaoGoal.new(goal_params)
      if @goal.save
        redirect_to admin_captacao_goals_path, notice: "Meta criada."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @goal.update(goal_params)
        redirect_to admin_captacao_goals_path, notice: "Meta atualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @goal.destroy
      redirect_to admin_captacao_goals_path, notice: "Meta removida."
    end

    private

    def set_goal
      @goal = CaptacaoGoal.find(params[:id])
    end

    def goal_params
      params.require(:captacao_goal).permit(:start_date, :end_date, :kind, :target, :foco_regiao, :foco_valor_min, :foco_valor_max)
    end
  end
end
