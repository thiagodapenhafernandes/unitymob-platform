# Validação de formulário: marca o controle inválido com a classe `is-invalid`
# e `aria-invalid="true"`
# (borda vermelha via ax_toast.css) em vez de envolvê-lo em
# <div class="field_with_errors">, que quebraria os layouts flex/grid dos forms.
# Aplica-se a todo o sistema (admin, público, field, wizard, login).
Rails.application.config.to_prepare do
  ActionView::Base.field_error_proc = proc do |html_tag, _instance|
    tag = html_tag.to_s

    if tag =~ /\A\s*<(input|select|textarea)\b/
      tag = if tag =~ /\bclass="/
              tag.sub(/\bclass="/, 'class="is-invalid ')
            else
              tag.sub(/\A(\s*<(?:input|select|textarea))\b/, '\\1 class="is-invalid"')
            end
      tag = tag.sub(/\A(\s*<(?:input|select|textarea))\b/, '\\1 aria-invalid="true"') unless tag.match?(/\baria-invalid=/)
      tag.html_safe
    else
      # labels e demais tags ficam intactos (sem wrapper, sem duplicar mensagem)
      tag.html_safe
    end
  end
end
