const clean = value=>String(value||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
export function filterWorkspace(items,{query='',facet='all',filters={},order='activity',direction='desc'}={}) {
  const values=v=>Array.isArray(v)?v:[v];
  const includes=(key,value)=>!filters[key]||!values(filters[key]).filter(Boolean).length||values(filters[key]).includes(String(value));
  const bool=(key,value)=>!filters[key]||String(Number(Boolean(value)))===filters[key];
  const list=items.filter(p=>
    (facet!=='mine'||p.mine) && (facet!=='opportunity'||p.opportunity)
    && (!['venda','locacao'].includes(facet)||p.purpose===facet)
    && (!filters.purpose||p.purpose===filters.purpose)
    && clean([p.code,p.title,p.neighborhood,p.city].join(' ')).includes(clean(query))
    && includes('category',p.category)&&includes('development',p.title)&&includes('owner',p.owner)
    && includes('status',p.rental?'Locação':'Venda')&&includes('city',p.city)&&includes('neighborhood',p.neighborhood)&&includes('situation',p.situation)&&includes('keys',p.keys)
    && (!filters.reference||String(p.code)===filters.reference)
    && (!filters.address||clean(p.address).includes(clean(filters.address)))&&(!filters.number||String(p.number)===filters.number)
    && (!filters.quick||values(filters.quick).every(q=>(p.quick_flags||[p.quick]).includes(q)))
    && (!filters.amenities||values(filters.amenities).every(q=>(p.amenities||[]).includes(q)))
    && (!filters.exchange_type||values(filters.exchange_type).every(q=>(p.exchange_type||[]).includes(q)))
    && bool('promotion',p.opportunity)&&bool('exchange',p.exchange)&&bool('installments',p.installments)&&bool('rental_management',p.rental_management)
    && (!filters.min_price||p.price_cents>=Number(filters.min_price)*100)
    && (!filters.max_price||p.price_cents<=Number(filters.max_price)*100)
    && ['bedrooms','suites','parking'].every(key=>!filters[key]||p[key]>=Number(filters[key]))
    && ['bedrooms','suites','bathrooms','parking','area_total','area'].every(key=>(!filters[key+'_min']||p[key]>=Number(filters[key+'_min']))&&(!filters[key+'_max']||p[key]<=Number(filters[key+'_max']))));
  const value=(p,key)=>key==='sale_price'?(p.rental?null:p.price_cents):key==='rental_price'?(p.rental?p.price_cents:null):key==='sale_m2'?(p.rental?null:p.price_cents/p.area):key==='rental_m2'?(p.rental?p.price_cents/p.area:null):key==='rental_total'?(p.rental?p.price_cents+p.condo_cents:null):p[key];
  if(order==='price_asc'||order==='price_desc')return list.sort((a,b)=>order==='price_asc'?a.price_cents-b.price_cents:b.price_cents-a.price_cents);
  return list.sort((a,b)=>{const x=value(a,order),y=value(b,order);if(x==null)return y==null?0:1;if(y==null)return -1;return String(x).localeCompare(String(y),'pt-BR',{numeric:true})*(direction==='asc'?1:-1);});
}
