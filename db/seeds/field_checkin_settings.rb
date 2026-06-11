# Feature flag e defaults do módulo de check-in de corretores em campo.
# Flag fica OFF por default — todas as rotas /field e integrações retornam
# 404 enquanto ela não for ligada via console/admin.

Setting.set(
  "field_checkin_enabled",
  Setting.get("field_checkin_enabled", "false"),
  "Liga/desliga o módulo de check-in geolocalizado de corretores (PWA /field)"
)

puts "  ✓ field_checkin_enabled: #{Setting.get('field_checkin_enabled')}"
