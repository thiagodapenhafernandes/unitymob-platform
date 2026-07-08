// Dashboard — operational cockpit.
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};

  const bars = [42, 58, 51, 67, 60, 78, 71, 84, 76, 90, 82, 128];
  const funnel = [
    { label: "Novos", value: 128, tone: "blue", pct: 100 },
    { label: "Em atendimento", value: 74, tone: "cyan", pct: 58 },
    { label: "Visita agendada", value: 39, tone: "amber", pct: 30 },
    { label: "Proposta", value: 18, tone: "purple", pct: 14 },
    { label: "Fechado", value: 9, tone: "green", pct: 7 },
  ];
  const pend = [
    { icon: "file-earmark-text", label: "Captações em rascunho", count: 6, tone: "amber" },
    { icon: "hourglass-split", label: "Leads represados", count: 9, tone: "red" },
    { icon: "hand-index-thumb", label: "Pedidos manuais pendentes", count: 3, tone: "amber" },
    { icon: "exclamation-triangle-fill", label: "Imóveis com erro de sync", count: 4, tone: "red" },
  ];
  const brokers = [
    { name: "Rafael Menezes", loja: "Centro", val: 14 },
    { name: "Bianca Toledo", loja: "Zona Sul", val: 11 },
    { name: "Diego Farias", loja: "Centro", val: 9 },
    { name: "Camila Prado", loja: "Litoral", val: 7 },
  ];

  function Dashboard() {
    return (
      <section>
        <header className="ax-dashboard-command">
          <div>
            <span className="ax-eyebrow">Cockpit operacional</span>
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 3 }}>
              <h1>Boa tarde, Marina</h1>
              <UM.Badge tone="blue">Admin</UM.Badge>
            </div>
            <p>terça-feira, 1 de julho · Campo ativo: 3 check-ins agora, 128 leads hoje.</p>
          </div>
          <div className="ax-dashboard-command__status"><i className="bi bi-hdd-network"></i> Operação</div>
          <UM.Badge tone="green" dot>Campo ativo</UM.Badge>
        </header>

        <div className="ax-dashboard-kpis">
          <UM.MetricCard label="Imóveis no catálogo" value="1.284" badge={<UM.Badge tone="green" dot>Ativos</UM.Badge>} hint="86 destaques · 12 empreendimentos" />
          <UM.MetricCard label="Leads hoje" value="128" badge={<UM.Badge tone="gray">+312 em 7d</UM.Badge>} hint="9 represados · 22 novos" />
          <UM.MetricCard label="Check-ins ativos" value="3" badge={<UM.Badge tone="green" dot>Ao vivo</UM.Badge>} hint="18 hoje · 1 suspeito" />
          <UM.MetricCard label="Regras de distribuição" value="8/12" badge={<UM.Badge tone="blue">4 c/ check-in</UM.Badge>} progress={66} />
        </div>

        <div className="ax-grid" style={{ gridTemplateColumns: "minmax(0,1.6fr) minmax(0,1fr)", marginBottom: 12 }}>
          <div className="ax-panel">
            <div className="ax-panel__head">
              <div><span className="ax-eyebrow">Aquisição</span><div className="ax-panel__title">Leads — últimos 30 dias</div></div>
              <UM.Badge tone="green" dot>+18% vs. mês anterior</UM.Badge>
            </div>
            <div style={{ padding: 16 }}>
              <div style={{ display: "flex", alignItems: "flex-end", gap: 6, height: 168 }}>
                {bars.map((b, i) => (
                  <div key={i} style={{ flex: 1, height: `${(b / 128) * 100}%`, background: i === bars.length - 1 ? "var(--primary)" : "var(--primary-soft)", borderRadius: "5px 5px 0 0", minHeight: 6 }} title={`${b} leads`} />
                ))}
              </div>
            </div>
          </div>

          <div className="ax-panel">
            <div className="ax-panel__head">
              <div><span className="ax-eyebrow">Funil</span><div className="ax-panel__title">Conversão comercial</div></div>
            </div>
            <div style={{ padding: "14px 16px", display: "grid", gap: 12 }}>
              {funnel.map((f) => (
                <div key={f.label}>
                  <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12.5, marginBottom: 4 }}>
                    <span style={{ color: "var(--ink-body)" }}>{f.label}</span>
                    <strong className="ax-num" style={{ color: "var(--ink)" }}>{f.value}</strong>
                  </div>
                  <div className="ax-progress"><i style={{ width: `${f.pct}%` }} /></div>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="ax-grid" style={{ gridTemplateColumns: "minmax(0,1fr) minmax(0,1.2fr)" }}>
          <div className="ax-panel">
            <div className="ax-panel__head">
              <div><span className="ax-eyebrow">Hoje</span><div className="ax-panel__title">Pendências</div></div>
              <UM.Badge tone="amber">4 pend.</UM.Badge>
            </div>
            <div style={{ padding: 10, display: "grid", gap: 6 }}>
              {pend.map((p) => (
                <a key={p.label} href="#" style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, padding: "9px 10px", border: "1px solid var(--line)", borderRadius: 8, background: "var(--surface-soft)", color: "var(--ink-body)", fontSize: 12.5 }}>
                  <span><i className={`bi bi-${p.icon}`} style={{ marginRight: 8, color: "var(--ink-muted)" }}></i>{p.label}</span>
                  <UM.Badge tone={p.tone}>{p.count}</UM.Badge>
                </a>
              ))}
            </div>
          </div>

          <div className="ax-panel">
            <div className="ax-panel__head">
              <div><span className="ax-eyebrow">Performance</span><div className="ax-panel__title">Top corretores</div></div>
              <a href="#" style={{ fontSize: 12, color: "var(--primary)" }}>Ver todos</a>
            </div>
            <table className="ax-table">
              <thead><tr><th>Corretor</th><th>Loja</th><th style={{ textAlign: "right" }}>Fechados</th></tr></thead>
              <tbody>
                {brokers.map((b, i) => (
                  <tr key={b.name}>
                    <td><span style={{ display: "inline-flex", alignItems: "center", gap: 8 }}><span className="ax-avatar" style={{ width: 24, height: 24, fontSize: 11 }}>{b.name.split(" ").map((n) => n[0]).slice(0, 2).join("")}</span><span className="ax-strong">{b.name}</span></span></td>
                    <td>{b.loja}</td>
                    <td className="ax-num" style={{ textAlign: "right" }}><strong style={{ color: "var(--ink)" }}>{b.val}</strong></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </section>
    );
  }

  window.UM_SCREENS.dashboard = Dashboard;
})();
