# frozen_string_literal: true

# Ponte de login para o app híbrido: o app já resolveu o servidor certo via
# discovery e navega (POST real de formulário, não fetch) direto pra cá com
# e-mail+senha, numa ÚNICA tela — sem passo de "digitar e-mail" antes do login.
#
# Herda TODA a lógica de autenticação (mirror, política de acesso, 2FA,
# remember_me, auditoria) do Admin::SessionsController — não duplica regra
# nenhuma, só troca a defesa de CSRF por token de sessão (que o app mobile,
# sendo outra origem, nunca teria). "Login CSRF" não se aplica aqui: quem
# chama este endpoint já precisa saber a senha da conta, então a credencial
# em si já é a prova de intenção — o mesmo raciocínio usado em
# Api::V1::Field::SessionsController.
module Mobile
  class SessionsController < Admin::SessionsController
    skip_before_action :verify_authenticity_token, raise: false
  end
end
