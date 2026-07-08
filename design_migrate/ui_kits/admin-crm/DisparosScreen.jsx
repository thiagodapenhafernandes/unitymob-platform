// WhatsApp — Disparos (campanhas por remetente).
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};

  const kpis = [
    { label: "Total", value: "4.270", hint: "no escopo filtrado", icon: "envelope", tone: "var(--gray)" },
    { label: "Enviadas", value: "3.890", hint: "mensagens enviadas", icon: "send", tone: "var(--purple)" },
    { label: "Falhas", value: "142", hint: "com falha", icon: "x-circle", tone: "var(--danger)" },
    { label: "Respostas", value: "612", hint: "recebidas", icon: "chat-dots", tone: "var(--cyan)" },
    { label: "Atendido", value: "418", hint: "fluxos atendidos", icon: "person-check", tone: "var(--success)" },
    { label: "Não atendido", value: "194", hint: "sem atendimento", icon: "person-x", tone: "var(--info)" },
    { label: "CPL", value: "R$ 3,80", hint: "custo por atendimento", icon: "calculator", tone: "var(--warning)" },
    { label: "Gasto total", value: "R$ 14.782", hint: "estimativa do período", icon: "wallet2", tone: "var(--entity-whatsapp)" },
  ];

  const camps = [
    { name: "Lançamento Praia Brava", desc: "Carrossel · 3 imóveis", status: { t: "Enviando", tone: "blue" }, grupo: "Lançamentos", tpl: "lancamento_praia_brava", lang: "pt_BR", sent: 1240, total: 1800, by: "Rafael M.", date: "01/07" },
    { name: "Reativação 60 dias", desc: "Base fria reengajada", status: { t: "Concluída", tone: "green" }, grupo: "Reativação", tpl: "reativacao_60d", lang: "pt_BR", sent: 900, total: 900, by: "Bianca T.", date: "30/06" },
    { name: "Feirão de Imóveis", desc: "Campanha de julho", status: { t: "Falha", tone: "red" }, grupo: "Feirão", tpl: "feirao_julho", lang: "pt_BR", sent: 320, total: 500, by: "Diego F.", date: "29/06" },
    { name: "Novos leads Moema", desc: "Boas-vindas automáticas", status: { t: "Agendada", tone: "gray" }, grupo: "—", tpl: "boas_vindas_lead", lang: "pt_BR", sent: 0, total: 640, by: "Camila P.", date: "02/07" },
    { name: "Pós-visita julho", desc: "Feedback pós-visita", status: { t: "Enviando", tone: "blue" }, grupo: "Follow-up", tpl: "pos_visita_feedback", lang: "pt_BR", sent: 210, total: 430, by: "Rafael M.", date: "01/07" },
  ];

  const fLabel = { display: "flex", flexDirection: "column", gap: 3, fontSize: 11, fontWeight: 600, color: "var(--ink-label)" };
  function Filter({ label, opts }) {
    return (
      <label style={fLabel}>{label}
        <select className="ax-input" style={{ height: 34, minWidth: 130 }}>{opts.map((o) => <option key={o}>{o}</option>)}</select>
      </label>
    );
  }

  function Disparos() {
    return (
      <section>
        <div className="ax-dashboard-command" style={{ gridTemplateColumns: "minmax(0,1fr) auto" }}>
          <div>
            <span className="ax-eyebrow">WhatsApp</span>
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 3 }}>
              <h1>Disparos</h1>
              <UM.Badge tone="green" dot>Conectado</UM.Badge>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--ink-muted)" }}>+55 47 99888-1020</span>
            </div>
            <p>Campanhas por remetente · volume, filtros comerciais e acompanhamento do envio.</p>
          </div>
          <div style={{ display: "inline-flex", gap: 6 }}>
            <UM.Button size="sm" icon="grid-3x2-gap">Templates</UM.Button>
            <UM.Button size="sm" variant="primary" icon="plus-lg">Nova campanha</UM.Button>
          </div>
        </div>

        {/* KPIs */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4,minmax(0,1fr))", gap: 12, marginBottom: 12 }}>
          {kpis.map((k) => (
            <div key={k.label} className="ax-panel" style={{ padding: "13px 15px" }}>
              <span style={{ width: 27, height: 27, borderRadius: 7, background: "var(--surface-header)", display: "grid", placeItems: "center", color: k.tone, fontSize: 13 }}><i className={`bi bi-${k.icon}`}></i></span>
              <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: ".03em", textTransform: "uppercase", color: "var(--ink-muted)", marginTop: 9 }}>{k.label}</div>
              <div className="ax-num" style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: 22, color: "var(--ink)", lineHeight: 1.1, marginTop: 2 }}>{k.value}</div>
              <div style={{ fontSize: 11, color: "var(--ink-faint)", marginTop: 2 }}>{k.hint}</div>
            </div>
          ))}
        </div>

        {/* Filters */}
        <div className="ax-panel" style={{ marginBottom: 12 }}>
          <div style={{ display: "flex", alignItems: "flex-end", gap: 10, padding: 12, flexWrap: "wrap" }}>
            <Filter label="Status" opts={["Todas", "Enviando", "Concluída", "Agendada", "Falha"]} />
            <Filter label="Criada por" opts={["Todos", "Rafael M.", "Bianca T.", "Diego F.", "Camila P."]} />
            <Filter label="Grupo" opts={["Todos", "Lançamentos", "Reativação", "Feirão", "Follow-up"]} />
            <label style={fLabel}>Campanha<input className="ax-input" style={{ height: 34, minWidth: 160 }} placeholder="Nome" /></label>
            <UM.Button size="sm" variant="primary" icon="funnel">Filtrar</UM.Button>
          </div>
        </div>

        {/* Campaigns table */}
        <div className="ax-panel">
          <div className="ax-panel__head">
            <div><span className="ax-eyebrow">5 campanhas</span><div className="ax-panel__title">Suas campanhas</div></div>
          </div>
          <table className="ax-table">
            <thead>
              <tr><th>Campanha</th><th>Status</th><th>Grupo</th><th>Template</th><th style={{ width: 170 }}>Progresso</th><th>Criada por</th><th>Data</th></tr>
            </thead>
            <tbody>
              {camps.map((c) => {
                const pct = c.total > 0 ? Math.round((c.sent / c.total) * 100) : 0;
                return (
                  <tr key={c.name}>
                    <td>
                      <a href="#" className="ax-strong" style={{ display: "block" }}><i className="bi bi-megaphone" style={{ marginRight: 6, color: "var(--ink-muted)" }}></i>{c.name}</a>
                      <span style={{ fontSize: 11, color: "var(--ink-muted)" }}>{c.desc}</span>
                    </td>
                    <td><UM.Badge tone={c.status.tone} dot={c.status.t === "Enviando"}>{c.status.t}</UM.Badge></td>
                    <td>{c.grupo}</td>
                    <td>
                      <strong style={{ color: "var(--ink)", fontSize: 12.5, fontFamily: "var(--font-mono)" }}>{c.tpl}</strong>
                      <span style={{ display: "block", fontSize: 11, color: "var(--ink-muted)" }}>{c.lang}</span>
                    </td>
                    <td>
                      <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11.5, marginBottom: 3 }}>
                        <span className="ax-num" style={{ color: "var(--ink-body)" }}>{c.sent} / {c.total}</span>
                        <strong className="ax-num" style={{ color: "var(--ink)" }}>{pct}%</strong>
                      </div>
                      <div className="ax-progress"><i style={{ width: `${pct}%` }} /></div>
                    </td>
                    <td>{c.by}</td>
                    <td className="ax-num">{c.date}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>
    );
  }

  window.UM_SCREENS.wa_disparos = Disparos;
})();
