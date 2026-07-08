// Imóveis — property catalog list.
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};

  const rows = [
    { code: "COD-84213", title: "Apartamento 2Q · Vila Mariana", tipo: "Apartamento", bairro: "Vila Mariana", preco: "R$ 680.000", trans: "Venda", status: { c: "green", t: "Publicado", dot: true }, corretor: "Rafael M.", dorm: 2, banho: 2, vaga: 1, area: "68 m²" },
    { code: "COD-84117", title: "Cobertura Duplex · Moema", tipo: "Cobertura", bairro: "Moema", preco: "R$ 1.900.000", trans: "Venda", status: { c: "green", t: "Publicado", dot: true }, corretor: "Bianca T.", dorm: 3, banho: 4, vaga: 3, area: "180 m²" },
    { code: "COD-83998", title: "Casa Térrea 3Q · Granja Viana", tipo: "Casa", bairro: "Granja Viana", preco: "R$ 920.000", trans: "Venda", status: { c: "amber", t: "Em revisão" }, corretor: "Diego F.", dorm: 3, banho: 3, vaga: 4, area: "210 m²" },
    { code: "COD-83820", title: "Studio Mobiliado · Centro", tipo: "Studio", bairro: "Centro", preco: "R$ 2.400 / mês", trans: "Locação", status: { c: "blue", t: "Novo" }, corretor: "Camila P.", dorm: 1, banho: 1, vaga: 0, area: "32 m²" },
    { code: "COD-83714", title: "Apartamento 3Q · Tatuapé", tipo: "Apartamento", bairro: "Tatuapé", preco: "R$ 750.000", trans: "Venda", status: { c: "red", t: "Erro sync" }, corretor: "Rafael M.", dorm: 3, banho: 2, vaga: 2, area: "92 m²" },
    { code: "COD-83590", title: "Casa Condomínio · Alphaville", tipo: "Casa", bairro: "Alphaville", preco: "R$ 2.400.000", trans: "Venda", status: { c: "gray", t: "Rascunho" }, corretor: "Bianca T.", dorm: 4, banho: 5, vaga: 4, area: "340 m²" },
  ];

  const chips = ["Todos", "Venda", "Locação", "Destaques", "Publicados", "Em revisão", "Com erro"];

  function Imoveis() {
    const [chip, setChip] = React.useState("Todos");
    return (
      <section>
        <div className="ax-dashboard-command" style={{ gridTemplateColumns: "minmax(0,1fr) auto" }}>
          <div>
            <span className="ax-eyebrow">Catálogo</span>
            <h1 style={{ marginTop: 3 }}>Imóveis</h1>
            <p>1.284 imóveis · 86 destaques · sincronizado há 6 min</p>
          </div>
          <div style={{ display: "inline-flex", gap: 6 }}>
            <UM.Button size="sm" icon="arrow-repeat">Sincronizar</UM.Button>
            <UM.Button size="sm" icon="download">Exportar</UM.Button>
            <UM.Button size="sm" variant="primary" icon="plus-lg" onClick={() => window.UM_GO("imovel_form")}>Novo imóvel</UM.Button>
          </div>
        </div>

        <div className="ax-panel">
          {/* Toolbar */}
          <div style={{ display: "flex", alignItems: "center", gap: 10, padding: 12, borderBottom: "1px solid var(--line-soft)", flexWrap: "wrap" }}>
            <UM.SearchInput placeholder="Buscar por código, título, endereço…" style={{ flex: "1 1 260px" }} />
            <UM.Button size="sm" icon="funnel">Filtros avançados</UM.Button>
            <UM.Button size="sm" icon="sliders">Colunas</UM.Button>
            <div className="ax-tabs" style={{ marginLeft: "auto" }}>
              <button className="ax-tab is-active"><i className="bi bi-list-ul"></i></button>
              <button className="ax-tab"><i className="bi bi-grid"></i></button>
              <button className="ax-tab"><i className="bi bi-geo-alt"></i></button>
            </div>
          </div>
          {/* Quick filter chips */}
          <div style={{ display: "flex", gap: 6, padding: "10px 12px", borderBottom: "1px solid var(--line-soft)", flexWrap: "wrap" }}>
            {chips.map((c) => (
              <button key={c} onClick={() => setChip(c)} className={c === chip ? "ax-btn ax-btn--sm ax-btn--primary" : "ax-btn ax-btn--sm"}>{c}</button>
            ))}
          </div>
          {/* Table */}
          <table className="ax-table">
            <thead>
              <tr>
                <th style={{ width: 34 }}><input type="checkbox" /></th>
                <th>Imóvel</th>
                <th>Tipo</th>
                <th>Bairro</th>
                <th>Config.</th>
                <th style={{ textAlign: "right" }}>Preço</th>
                <th>Status</th>
                <th>Corretor</th>
                <th style={{ width: 44 }}></th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.code}>
                  <td><input type="checkbox" /></td>
                  <td>
                    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                      <span style={{ width: 40, height: 40, borderRadius: 6, background: "var(--surface-header)", display: "grid", placeItems: "center", color: "var(--ink-faint)", flex: "none" }}><i className="bi bi-image"></i></span>
                      <div style={{ minWidth: 0 }}>
                        <a href="#" className="ax-strong" style={{ display: "block", cursor: "pointer" }} onClick={(e) => { e.preventDefault(); window.UM_GO("imovel_form"); }}>{r.title}</a>
                        <span style={{ fontSize: 11, color: "var(--ink-muted)", fontFamily: "var(--font-mono)" }}>{r.code} · {r.trans}</span>
                      </div>
                    </div>
                  </td>
                  <td>{r.tipo}</td>
                  <td>{r.bairro}</td>
                  <td>
                    <span style={{ display: "inline-flex", gap: 9, color: "var(--ink-muted)", fontSize: 12 }}>
                      <span title="Dormitórios"><i className="bi bi-door-closed"></i> {r.dorm}</span>
                      <span title="Banheiros"><i className="bi bi-droplet"></i> {r.banho}</span>
                      <span title="Vagas"><i className="bi bi-car-front"></i> {r.vaga}</span>
                      <span title="Área"><i className="bi bi-arrows-fullscreen"></i> {r.area}</span>
                    </span>
                  </td>
                  <td className="ax-num" style={{ textAlign: "right" }}><strong style={{ color: "var(--ink)" }}>{r.preco}</strong></td>
                  <td><UM.Badge tone={r.status.c} dot={r.status.dot}>{r.status.t}</UM.Badge></td>
                  <td>{r.corretor}</td>
                  <td><button className="ax-ico-btn" aria-label="Ações"><i className="bi bi-three-dots-vertical"></i></button></td>
                </tr>
              ))}
            </tbody>
          </table>
          {/* Footer / pagination */}
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "10px 14px", fontSize: 12.5, color: "var(--ink-muted)" }}>
            <span>Mostrando 1–6 de 1.284</span>
            <div style={{ display: "inline-flex", gap: 6 }}>
              <UM.Button size="sm" icon="chevron-left" disabled>Anterior</UM.Button>
              <UM.Button size="sm" iconRight="chevron-right">Próximo</UM.Button>
            </div>
          </div>
        </div>
      </section>
    );
  }

  window.UM_SCREENS.imoveis = Imoveis;
})();
