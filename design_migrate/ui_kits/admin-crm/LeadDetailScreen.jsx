// Leads — detalhe/edição do lead (exemplo preenchido).
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};
  const go = (id) => window.UM_GO && window.UM_GO(id);

  const timeline = [
    { icon: "whatsapp", tone: "var(--entity-whatsapp)", t: "Mensagem no WhatsApp", d: "Perfeito, podemos agendar a visita?", time: "Hoje 12:41" },
    { icon: "telephone", tone: "var(--info)", t: "Ligação registrada", d: "Retornou interesse no apto de Vila Mariana. Pediu 2ª visita.", time: "Hoje 10:12" },
    { icon: "envelope", tone: "var(--purple)", t: "E-mail enviado", d: "Ficha completa do imóvel COD-84213.", time: "Ontem 19:04" },
    { icon: "person-plus", tone: "var(--success)", t: "Lead criado", d: "Origem: Portal ZAP · distribuído para Rafael M.", time: "Ontem 18:30" },
  ];

  function Row({ k, v }) {
    return <div style={{ display: "flex", justifyContent: "space-between", gap: 10, padding: "8px 0", borderBottom: "1px solid var(--line-soft)", fontSize: 12.5 }}><span style={{ color: "var(--ink-muted)" }}>{k}</span><strong style={{ color: "var(--ink)", textAlign: "right" }}>{v}</strong></div>;
  }

  function LeadDetail() {
    return (
      <section>
        <div className="ax-dashboard-command" style={{ gridTemplateColumns: "minmax(0,1fr) auto" }}>
          <div>
            <button className="ax-btn ax-btn--sm" onClick={() => go("leads")} style={{ marginBottom: 8 }}><i className="bi bi-arrow-left ax-ico"></i> Voltar ao funil</button>
            <span className="ax-eyebrow">Comercial · Lead</span>
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 3 }}>
              <h1>Marina Costa</h1>
              <UM.Badge tone="blue" dot>Novo</UM.Badge>
              <UM.LeadLabelChip color="red">Quente</UM.LeadLabelChip>
            </div>
            <p>+55 11 98765-4321 · marina.costa@email.com · lead há 1 dia</p>
          </div>
          <div style={{ display: "inline-flex", gap: 6 }}>
            <UM.Button size="sm" icon="whatsapp" onClick={() => go("wa_atendimento")}>Atender</UM.Button>
            <UM.Button size="sm" icon="pencil">Editar</UM.Button>
            <UM.Button size="sm" variant="primary" icon="file-earmark-text">Nova proposta</UM.Button>
          </div>
        </div>

        <div className="ax-grid" style={{ gridTemplateColumns: "minmax(0,1.4fr) minmax(0,1fr)" }}>
          <div className="ax-panel">
            <div className="ax-panel__head"><div><span className="ax-eyebrow">Histórico</span><div className="ax-panel__title">Linha do tempo</div></div><UM.Badge tone="gray">4 interações</UM.Badge></div>
            <div style={{ padding: 16, display: "grid", gap: 14 }}>
              {timeline.map((e, i) => (
                <div key={i} style={{ display: "flex", gap: 12 }}>
                  <span style={{ width: 30, height: 30, borderRadius: 8, background: "var(--surface-header)", color: e.tone, display: "grid", placeItems: "center", flex: "none" }}><i className={`bi bi-${e.icon}`}></i></span>
                  <div style={{ minWidth: 0, flex: 1 }}>
                    <div style={{ display: "flex", justifyContent: "space-between", gap: 10 }}><strong style={{ fontSize: 12.5, color: "var(--ink)" }}>{e.t}</strong><span style={{ fontSize: 11, color: "var(--ink-faint)", flex: "none" }}>{e.time}</span></div>
                    <div style={{ fontSize: 12, color: "var(--ink-body)", marginTop: 2 }}>{e.d}</div>
                  </div>
                </div>
              ))}
            </div>
            <div style={{ display: "flex", gap: 8, padding: 12, borderTop: "1px solid var(--line-soft)" }}>
              <input className="ax-input" placeholder="Registrar contato ou nota…" style={{ flex: 1 }} />
              <UM.Button size="sm" variant="primary" icon="send">Registrar</UM.Button>
            </div>
          </div>

          <div style={{ display: "grid", gap: 12, alignContent: "start" }}>
            <div className="ax-panel">
              <div className="ax-panel__head"><div><span className="ax-eyebrow">Dados</span><div className="ax-panel__title">Informações do lead</div></div></div>
              <div style={{ padding: "6px 16px 12px" }}>
                <Row k="Origem" v="Portal ZAP" />
                <Row k="Etapa do funil" v="Novo" />
                <Row k="Corretor" v="Rafael M." />
                <Row k="Imóvel de interesse" v="Apto 302 · Vila Mariana" />
                <Row k="Faixa de valor" v="R$ 650–720 mil" />
                <Row k="Financiamento" v="Sim · pré-aprovado" />
              </div>
            </div>
            <div className="ax-panel">
              <div className="ax-panel__head"><div><span className="ax-eyebrow">Contexto</span><div className="ax-panel__title">Vínculos</div></div></div>
              <div style={{ padding: 14, display: "grid", gap: 8 }}>
                <UM.ContextPin type="property">Apto 302 · Vila Mariana</UM.ContextPin>
                <UM.ContextPin type="proposal">Proposta #1042 · rascunho</UM.ContextPin>
              </div>
            </div>
            <UM.Button block icon="calendar-event">Agendar visita</UM.Button>
          </div>
        </div>
      </section>
    );
  }

  window.UM_SCREENS.lead_detail = LeadDetail;
})();
