// Leads — kanban funnel board.
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};

  const COLUMNS = [
    { key: "novo", eyebrow: "Entrada", title: "Novos", tone: "blue", cards: [
      { name: "Marina Costa", origem: "Portal ZAP", imovel: "Apto 2Q · Vila Mariana", valor: "R$ 680 mil", labels: [{ c: "red", t: "Quente" }], time: "12 min" },
      { name: "Eduardo Lima", origem: "Meta Ads", imovel: "Cobertura · Moema", valor: "R$ 1,9 mi", labels: [{ c: "cyan", t: "Financiamento" }], time: "38 min" },
      { name: "Patrícia Nunes", origem: "WhatsApp", imovel: "Casa 3Q · Granja", valor: "R$ 920 mil", labels: [], time: "1 h" },
    ]},
    { key: "atendimento", eyebrow: "Comercial", title: "Em atendimento", tone: "cyan", cards: [
      { name: "Rafael Souza", origem: "Indicação", imovel: "Studio · Centro", valor: "R$ 340 mil", labels: [{ c: "amber", t: "Retornar" }], time: "3 h" },
      { name: "Juliana Alves", origem: "Portal OLX", imovel: "Apto 3Q · Tatuapé", valor: "R$ 750 mil", labels: [{ c: "green", t: "Visita agendada" }], time: "5 h" },
    ]},
    { key: "proposta", eyebrow: "Negociação", title: "Proposta", tone: "purple", cards: [
      { name: "Carlos Prado", origem: "Site", imovel: "Casa · Alphaville", valor: "R$ 2,4 mi", labels: [{ c: "purple", t: "Proposta enviada" }], time: "1 d" },
    ]},
    { key: "fechado", eyebrow: "Ganho", title: "Fechado", tone: "green", cards: [
      { name: "Beatriz Rocha", origem: "Portal ZAP", imovel: "Apto 2Q · Pinheiros", valor: "R$ 890 mil", labels: [{ c: "green", t: "Contrato" }], time: "2 d" },
    ]},
  ];

  function LeadCard({ c }) {
    return (
      <article className="ax-board__card" style={{ cursor: "pointer" }} onClick={() => window.UM_GO("lead_detail")}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8 }}>
          <span style={{ display: "inline-flex", alignItems: "center", gap: 8, minWidth: 0 }}>
            <span className="ax-avatar" style={{ width: 26, height: 26, fontSize: 11 }}>{c.name.split(" ").map((n) => n[0]).slice(0, 2).join("")}</span>
            <strong style={{ fontSize: 13, color: "var(--ink)" }}>{c.name}</strong>
          </span>
          <button className="ax-ico-btn" aria-label="Mais"><i className="bi bi-three-dots-vertical"></i></button>
        </div>
        <div style={{ fontSize: 12, color: "var(--ink-body)" }}><i className="bi bi-house-door" style={{ color: "var(--ink-faint)", marginRight: 5 }}></i>{c.imovel}</div>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <strong className="ax-num" style={{ fontSize: 13, color: "var(--ink)" }}>{c.valor}</strong>
          <span className="ax-badge ax-badge--gray" style={{ fontSize: 10.5 }}><i className="bi bi-broadcast-pin" style={{ fontSize: 11 }}></i>{c.origem}</span>
        </div>
        {c.labels.length > 0 && (
          <div style={{ display: "flex", gap: 4, flexWrap: "wrap" }}>
            {c.labels.map((l, i) => <UM.LeadLabelChip key={i} color={l.c}>{l.t}</UM.LeadLabelChip>)}
          </div>
        )}
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", borderTop: "1px solid var(--line-soft)", paddingTop: 8, fontSize: 11, color: "var(--ink-muted)" }}>
          <span><i className="bi bi-clock" style={{ marginRight: 4 }}></i>{c.time}</span>
          <span style={{ display: "inline-flex", gap: 6 }}>
            <i className="bi bi-whatsapp" style={{ color: "var(--entity-whatsapp)" }}></i>
            <i className="bi bi-telephone"></i>
            <i className="bi bi-calendar-event"></i>
          </span>
        </div>
      </article>
    );
  }

  function Leads() {
    return (
      <section>
        <div className="ax-dashboard-command" style={{ gridTemplateColumns: "minmax(0,1fr) auto" }}>
          <div>
            <span className="ax-eyebrow">Comercial</span>
            <h1 style={{ marginTop: 3 }}>Funil de Leads</h1>
            <p>231 leads ativos · atualizado agora</p>
          </div>
          <div style={{ display: "inline-flex", gap: 6 }}>
            <UM.Button size="sm" icon="funnel">Filtros</UM.Button>
            <UM.Button size="sm" icon="download">Exportar</UM.Button>
            <UM.Button size="sm" variant="primary" icon="plus-lg" onClick={() => window.UM_GO("lead_detail")}>Novo lead</UM.Button>
          </div>
        </div>

        <div className="ax-board">
          {COLUMNS.map((col) => (
            <div key={col.key} className="ax-board__column">
              <div className="ax-board__col-head">
                <div>
                  <span className="ax-board__col-eyebrow">{col.eyebrow}</span>
                  <span className="ax-board__col-title">{col.title}</span>
                </div>
                <span className="ax-board__col-count">{col.cards.length}</span>
              </div>
              <div className="ax-board__col-body">
                {col.cards.map((c, i) => <LeadCard key={i} c={c} />)}
              </div>
            </div>
          ))}
        </div>
      </section>
    );
  }

  window.UM_SCREENS.leads = Leads;
})();
