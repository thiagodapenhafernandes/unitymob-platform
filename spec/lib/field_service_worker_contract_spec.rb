require "rails_helper"

RSpec.describe "field service worker contract" do
  let(:worker_path) { Rails.root.join("public/field-service-worker.js") }
  let(:worker_source) { File.read(worker_path) }

  it "usa escopo raiz para permitir que o clique do push abra leads no admin" do
    field_layout = File.read(Rails.root.join("app/views/layouts/field.html.erb"))
    admin_push_partial = File.read(Rails.root.join("app/views/layouts/_admin_push_subscriptions.html.erb"))
    pwa_service_worker_partial = File.read(Rails.root.join("app/views/layouts/_pwa_service_worker.html.erb"))

    expect(field_layout).to include('navigator.serviceWorker.register("/field-service-worker.js", { scope: "/", updateViaCache: "none" })')
    expect(admin_push_partial).to include('navigator.serviceWorker.register("/field-service-worker.js", { scope: "/", updateViaCache: "none" })')
    expect(pwa_service_worker_partial).to include("var workerPath = (isIosDevice || isAndroid || isStandalone || isMobileViewport) ? '/field-service-worker.js' : '/service-worker.js';")
    expect(pwa_service_worker_partial).to include("navigator.serviceWorker.register(workerPath, { scope: '/', updateViaCache: 'none' })")
  end

  it "normaliza o destino do clique antes de abrir a janela" do
    expect(worker_source).to include('const CACHE_VERSION = "v8"')
    expect(worker_source).to include("function notificationTargetUrl(raw)")
    expect(worker_source).to include("function sameClientUrl(clientUrl, targetUrl)")
    expect(worker_source).to include("clients.openWindow(target.href)")
  end

  it "preserva fallback offline para navegacoes fora do field sem cachear paginas admin" do
    expect(worker_source).to include('const OFFLINE_FALLBACK_PAGE = "/offline.html"')
    expect(worker_source).to include('!url.pathname.startsWith("/field") && request.method === "GET" && request.mode === "navigate"')
    expect(worker_source).to include("caches.match(OFFLINE_FALLBACK_PAGE)")
  end
end
