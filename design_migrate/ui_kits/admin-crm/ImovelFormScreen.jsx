// Imóveis — formulário de edição (exemplo preenchido).
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};
  const go = (id) => window.UM_GO && window.UM_GO(id);

  const fld = { display: "flex", flexDirection: "column", gap: 4 };
  const lbl = { fontSize: 11.5, fontWeight: 600, color: "var(--ink-label)" };
  function F({ label, span = 3, children }) {
    return <label style={{ ...fld, gridColumn: `span ${span}` }}><span style={lbl}>{label}</span>{children}</label>;
  }
  const inp = (props) => <input className="ax-input" {...props} />;
  const sel = (opts, value) => <select className="ax-input" defaultValue={value}>{opts.map((o) => <option key={o}>{o}</option>)}</select>;
  const grid = { display: "grid", gridTemplateColumns: "repeat(12,1fr)", gap: 14, padding: 16 };
  const head = (eb, t, top) => (
    <div className="ax-panel__head" style={top ? { borderTop: "1px solid var(--line-soft)" } : null}><div><span className="ax-eyebrow">{eb}</span><div className="ax-panel__title">{t}</div></div></div>
  );

  const TABS = ["Dados", "Localização", "Características", "Mídia", "Publicação"];

  function ImovelForm() {
    const [tab, setTab] = React.useState("Dados");
    return (
      <section>
        <div className="ax-dashboard-command" style={{ gridTemplateColumns: "minmax(0,1fr) auto" }}>
          <div>
            <button className="ax-btn ax-btn--sm" onClick={() => go("imoveis")} style={{ marginBottom: 8 }}><i className="bi bi-arrow-left ax-ico"></i> Voltar ao catálogo</button>
            <span className="ax-eyebrow">Catálogo · Edição</span>
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 3 }}>
              <h1>Editar imóvel</h1>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 12.5, color: "var(--ink-muted)" }}>COD-84213</span>
              <UM.Badge tone="green" dot>Publicado</UM.Badge>
            </div>
            <p>Apartamento 2Q · Vila Mariana · sincronizado com Vista há 6 min.</p>
          </div>
          <div style={{ display: "inline-flex", gap: 6 }}>
            <UM.Button size="sm" icon="eye">Ver no site</UM.Button>
            <UM.Button size="sm" icon="stars">Descrição por IA</UM.Button>
            <UM.Button size="sm" variant="primary" icon="check-lg">Salvar alterações</UM.Button>
          </div>
        </div>

        <div className="ax-tabs" style={{ marginBottom: 12 }}>
          {TABS.map((t) => <button key={t} className={t === tab ? "ax-tab is-active" : "ax-tab"} onClick={() => setTab(t)}>{t}</button>)}
        </div>

        <div className="ax-panel">
          {head("Identidade", "Dados principais")}
          <div style={grid}>
            <F label="Título do anúncio" span={8}>{inp({ defaultValue: "Apartamento 2Q · Vila Mariana" })}</F>
            <F label="Código" span={4}>{inp({ defaultValue: "COD-84213", disabled: true })}</F>
            <F label="Tipo" span={3}>{sel(["Apartamento", "Casa", "Cobertura", "Studio", "Terreno", "Comercial"], "Apartamento")}</F>
            <F label="Transação" span={3}>{sel(["Venda", "Locação", "Venda e locação"], "Venda")}</F>
            <F label="Status" span={3}>{sel(["Rascunho", "Em revisão", "Publicado"], "Publicado")}</F>
            <F label="Corretor responsável" span={3}>{sel(["Rafael M.", "Bianca T.", "Diego F.", "Camila P."], "Rafael M.")}</F>
          </div>

          {head("Valores", "Preço e custos", true)}
          <div style={grid}>
            <F label="Preço (R$)" span={4}>{inp({ defaultValue: "680.000", inputMode: "numeric" })}</F>
            <F label="Condomínio (R$)" span={4}>{inp({ defaultValue: "620", inputMode: "numeric" })}</F>
            <F label="IPTU/ano (R$)" span={4}>{inp({ defaultValue: "2.400", inputMode: "numeric" })}</F>
          </div>

          {head("Localização", "Endereço", true)}
          <div style={grid}>
            <F label="CEP" span={3}>{inp({ defaultValue: "04101-000" })}</F>
            <F label="Logradouro" span={6}>{inp({ defaultValue: "Rua Domingos de Morais, 1203" })}</F>
            <F label="Número" span={3}>{inp({ defaultValue: "1203" })}</F>
            <F label="Bairro" span={4}>{inp({ defaultValue: "Vila Mariana" })}</F>
            <F label="Cidade" span={4}>{inp({ defaultValue: "São Paulo" })}</F>
            <F label="UF" span={4}>{sel(["SP", "RJ", "MG", "SC", "PR", "RS"], "SP")}</F>
          </div>

          {head("Configuração", "Características", true)}
          <div style={grid}>
            <F label="Dormitórios" span={3}>{inp({ type: "number", defaultValue: 2 })}</F>
            <F label="Banheiros" span={3}>{inp({ type: "number", defaultValue: 2 })}</F>
            <F label="Vagas" span={3}>{inp({ type: "number", defaultValue: 1 })}</F>
            <F label="Área útil (m²)" span={3}>{inp({ type: "number", defaultValue: 68 })}</F>
            <F label="Descrição" span={12}><textarea className="ax-input" rows={4} style={{ resize: "vertical", height: "auto", paddingTop: 8 }} defaultValue="Apartamento reformado de 2 dormitórios na Vila Mariana, 68m², 1 vaga, próximo ao metrô Santa Cruz. Sala ampla, cozinha planejada e varanda com boa vista." /></F>
          </div>

          <div style={{ display: "flex", justifyContent: "space-between", gap: 8, padding: 14, borderTop: "1px solid var(--line-soft)", position: "sticky", bottom: 0, background: "var(--surface)" }}>
            <UM.Button size="sm" icon="trash">Excluir</UM.Button>
            <div style={{ display: "inline-flex", gap: 8 }}>
              <UM.Button size="sm" onClick={() => go("imoveis")}>Cancelar</UM.Button>
              <UM.Button size="sm" variant="primary" icon="check-lg">Salvar alterações</UM.Button>
            </div>
          </div>
        </div>
      </section>
    );
  }

  window.UM_SCREENS.imovel_form = ImovelForm;
})();
