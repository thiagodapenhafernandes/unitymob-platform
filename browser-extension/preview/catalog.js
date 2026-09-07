const rows = [
  ['1842','Ed. Horizonte','Apartamento','Centro',480000,2,1,1,78,'venda','mobiliado'],
  ['2310','Vista Parque','Apartamento','Jardim',620000,3,1,2,105,'venda','sacada'],
  ['1405','Epic Tower','Apartamento','Barra Sul',18500000,4,4,4,291,'venda','frente_mar'],
  ['2281','Epic Tower','Apartamento','Barra Sul',16000000,4,4,6,310,'venda','frente_mar'],
  ['3100','Casa das Palmeiras','Casa','Nações',950000,3,2,2,180,'venda','piscina'],
  ['4200','Residencial Atlântico','Apartamento','Centro',4500,2,1,1,85,'locacao','mobiliado'],
  ['4300','Sala Empresarial','Comercial','Centro',2800,0,0,1,48,'locacao',''],
  ['5100','Jardim das Flores','Casa','Jardim',740000,3,1,2,140,'venda','sacada']
];
export const catalog = rows.map(([id,title,category,neighborhood,price,bedrooms,suites,parking,area,purpose,quick]) => ({
  id,code:id,title,card_title:title,category,neighborhood,price_cents:price*100,bedrooms,suites,parking,area,purpose,quick,
  city:'Balneário Camboriú',rental:purpose==='locacao',condo_cents:category==='Casa'?0:65000,iptu_cents:180000,
  removable:true,public_path:'/imovel-demonstrativo',photo_urls:[]
}));
const normalize = value => String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
export function searchCatalog({query='',purpose='venda',filters={}}, linked = new Set()) {
  return catalog.filter(p => p.purpose===purpose
    && normalize([p.code,p.title,p.neighborhood,p.city].join(' ')).includes(normalize(query))
    && (!filters.category || p.category===filters.category)
    && (!filters.quick || p.quick===filters.quick)
    && (!filters.min_price || p.price_cents>=Number(filters.min_price)*100)
    && (!filters.max_price || p.price_cents<=Number(filters.max_price)*100)
    && ['bedrooms','suites','parking'].every(key=>!filters[key] || p[key]>=Number(filters[key]))
  ).map(p=>({...p,linked:linked.has(p.id)}));
}
