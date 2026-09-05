require 'rails_helper'
RSpec.describe 'Meu perfil', type: :request do
  include Devise::Test::IntegrationHelpers
  let(:user) { create(:admin_user) }
  before { host! 'localhost'; sign_in user }
  it 'permite ao corretor abrir seu próprio perfil sem permissão de gestão' do
    get edit_admin_my_profile_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Foto de perfil', 'Senha atual', 'ax-mobile-detail-header')
  end
  it 'exige senha atual e confirmação sem alterar privilégios nem outro usuário' do
    other = create(:admin_user)
    patch admin_my_profile_path, params: { current_password: 'errada', admin_user: { password: 'nova-senha-123', password_confirmation: 'nova-senha-123' } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.valid_password?('password123')).to be(true)
    patch admin_my_profile_path, params: { id: other.id, current_password: 'password123', admin_user: { password: 'nova-senha-123', password_confirmation: 'nova-senha-123', role: 'admin', email: other.email } }
    expect(response).to redirect_to(edit_admin_my_profile_path)
    expect(user.reload.valid_password?('nova-senha-123')).to be(true)
    expect(other.reload.valid_password?('password123')).to be(true)
    expect(user.role).to eq('editor')
    get edit_admin_my_profile_path
    expect(response).to have_http_status(:ok)
  end
  it 'rejeita confirmação diferente e arquivos não permitidos' do
    patch admin_my_profile_path, params: { current_password: 'password123', admin_user: { password: 'nova-senha-123', password_confirmation: 'outra' } }
    expect(response).to have_http_status(:unprocessable_entity)
    upload = Rack::Test::UploadedFile.new(StringIO.new('bad'), 'text/plain', original_filename: 'foto.txt')
    patch admin_my_profile_path, params: { admin_user: { avatar: upload } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.avatar).not_to be_attached
  end
  it 'atualiza apenas a foto sem exigir troca de senha' do
    bytes = Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a8GQAAAAASUVORK5CYII=')
    upload = Rack::Test::UploadedFile.new(StringIO.new(bytes), 'image/png', original_filename: 'foto.png')
    patch admin_my_profile_path, params: { admin_user: { avatar: upload, password: '', password_confirmation: '' } }
    expect(response).to redirect_to(edit_admin_my_profile_path)
    expect(user.reload.avatar).to be_attached
    expect(user.valid_password?('password123')).to be(true)
  end
end
