// WhatsApp — Templates (modelos aprovados pela Meta).
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};

  const rows = [
    { name: "boas_vindas_lead", hint: "Disponível para campanhas", type: "Texto", cat: "Utilidade", lang: "pt_BR", status: "Aprovado", tone: "green", approved: true },
    { name: "agendamento_visita", hint: "Disponível para campanhas", type: "Mídia", cat: "Marketing", lang: "pt_BR", status: "Aprovado", tone: "green", approved: true },
    { name: "proposta_enviada", hint: "Disponível para campanhas", type: "Texto", cat: "Utilidade", lang: "pt_BR", status: "Aprovado", tone: "green", approved: true },
    { name: "lancamento_praia_brava", hint: "Disponível para campanhas", type: "Carrossel", cat: "Marketing", lang: "pt_BR", status: "Aprovado", tone: "green", approved: true },
    { name: "reativacao_60d", hint: "Aguardando revisão", type: "Texto", cat: "Marketing", lang: "pt_BR", status: "Em análise", tone: "amber", approved: false },
    { name: "pos_visita_feedback", hint: "Disponível para campanhas", type: "Flow", cat: "Utilidade", lang: "pt_BR", status: "Aprovado", tone: "green", approved: true },
    { name: "feirao_julho", hint: "Reprovado pela Meta", type: "Mídia", cat: "Marketing", lang: "pt_BR", status: "Rejeitado", tone: "red", approved: false },
  ];

  const fLabel = { display: "flex", flexDirection: "column", gap: 3, fontSize: 11, fontWeight: 600, color: "var(--ink-label)" };
  function Filter({ label, opts }) {
    return (
      <label style={fLabel}>{label}
        <select className="ax-input" style={{ height: 34, minWidth: 132 }}>{opts.map((o) => <option key={o}>{o}</option>)}</select>
      </label>
    );
  }

  function Templates() {
    return (
      <section>
        <div className="ax-dashboard-command" style={{ gridTemplateColumns: "minmax(0,1fr) auto" }}>
          <div>
            <span className="ax-eyebrow">WhatsApp</span>
            <h1 style={{ marginTop: 3 }}>Templates</h1>
            <p>Modelos aprovados pela Meta · usados nas campanhas de disparo.</p>
          </div>
          <div style={{ display: "inline-flex", gap: 6, alignItems: "center" }}>
            <UM.Badge tone="green" dot>12 aprovados</UM.Badge>
            <UM.Badge tone="amber" dot>3 em análise</UM.Badge>
            <UM.Button size="sm" icon="arrow-repeat">Sincronizar</UM.Button>
            <UM.Button size="sm" variant="primary" icon="plus-lg">Novo template</UM.Button>
          </div>
        </div>

        <div className="ax-panel">
          <div style={{ display: "flex", alignItems: "flex-end", gap: 10, padding: 12, borderBottom: "1px solid var(--line-soft)", flexWrap: "wrap" }}>
            <UM.SearchInput placeholder="Buscar por nome…" style={{ flex: "1 1 220px" }} />
            <Filter label="Status" opts={["Todos", "Aprovado", "Em análise", "Rejeitado"]} />
            <Filter label="Categoria" opts={["Todas", "Utilidade", "Marketing", "Autenticação"]} />
            <Filter label="Tipo" opts={["Todos", "Texto", "Mídia", "Carrossel", "Flow"]} />
            <UM.Button size="sm" icon="funnel">Filtrar</UM.Button>
          </div>
          <table className="ax-table">
            <thead>
              <tr><th>Nome</th><th>Tipo</th><th>Categoria</th><th>Idioma</th><th>Status</th><th style={{ width: 200 }}>Ações</th></tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.name}>
                  <td>
                    <a href="#" className="ax-strong" style={{ display: "block", fontFamily: "var(--font-mono)", fontSize: 12.5 }}>{r.name}</a>
                    <span style={{ fontSize: 11, color: "var(--ink-muted)" }}>{r.hint}</span>
                  </td>
                  <td>{r.type}</td>
                  <td><UM.Badge tone="gray">{r.cat}</UM.Badge></td>
                  <td style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--ink-muted)" }}>{r.lang}</td>
                  <td><UM.Badge tone={r.tone} dot>{r.status}</UM.Badge></td>
                  <td>
                    <div style={{ display: "inline-flex", gap: 6 }}>
                      <UM.Button size="sm" icon="eye">Prévia</UM.Button>
                      {r.approved && <UM.Button size="sm" variant="primary" icon="megaphone">Criar campanha</UM.Button>}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    );
  }

  window.UM_SCREENS.wa_templates = Templates;
})();
