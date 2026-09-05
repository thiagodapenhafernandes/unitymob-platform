class QueuePreferencesController < ApplicationController
  def update
    return head :forbidden unless current_staff.operator?
    allowed={'status'=>['',*Support::Ticket::STATUSES],'origin'=>['','ativo','receptivo'],'mine'=>['','1'],'order'=>['oldest','newest']}
    values=params.require(:preferences).permit(*allowed.keys).to_h
    return head :unprocessable_entity unless values.keys.sort==allowed.keys.sort && values.all?{|key,value|allowed[key].include?(value)}
    current_staff.update!(queue_preferences:values)
    head :no_content
  end
end
