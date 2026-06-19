# Build do Tailwind do CRM (/admin) — SEPARADO do build do front.
# Usa o binário standalone que vem com a gem tailwindcss-rails.
namespace :admin_tailwind do
  def admin_tailwind_executable
    gem_dir = Gem.loaded_specs["tailwindcss-rails"]&.gem_dir
    raise "gem tailwindcss-rails não encontrada" unless gem_dir

    # binário real fica em exe/<plataforma>/tailwindcss (o exe/tailwindcss é só um wrapper Ruby)
    candidates = Dir[File.join(gem_dir, "exe", "*", "tailwindcss")]
    bin = candidates.find { |f| File.executable?(f) }
    raise "binário tailwindcss não encontrado em #{gem_dir}/exe" unless bin

    bin
  end

  def admin_tailwind_args
    [
      "-c", Rails.root.join("config/admin_tailwind.config.js").to_s,
      "-i", Rails.root.join("app/assets/stylesheets/admin_tailwind.css").to_s,
      "-o", Rails.root.join("app/assets/builds/admin_tailwind.css").to_s,
    ]
  end

  desc "Compila o Tailwind do CRM (/admin)"
  task build: :environment do
    system(admin_tailwind_executable, *admin_tailwind_args, "--minify") || abort("admin_tailwind:build falhou")
  end

  desc "Observa e recompila o Tailwind do CRM ao salvar"
  task watch: :environment do
    system(admin_tailwind_executable, *admin_tailwind_args, "--watch")
  end
end

# Garante que o admin entra no precompile de produção junto com o resto.
if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance(["admin_tailwind:build"])
end
