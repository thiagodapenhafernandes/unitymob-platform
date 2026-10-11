const scalarKeys = ['min_price','max_price','suites','bedrooms','parking','reference','address','number','promotion','exchange','installments','rental_management',...['bedrooms','suites','bathrooms','parking','area_total','area'].flatMap(key=>[`${key}_min`,`${key}_max`])];
const listKeys = ['category','quick','development','owner','status','city','neighborhood','situation','keys','amenities','exchange_type'];
export function catalogSearchParams(message) {
  const result={};
  for(const key of [...scalarKeys,...listKeys]) {
    const raw=message.filters?.[key];
    if(raw==null)continue;
    if(Array.isArray(raw)) {
      if(!listKeys.includes(key)||raw.length>30||raw.some(v=>typeof v!=='string'||v.length>100))throw new Error('invalid_fields');
      result[key]=raw;
    } else {
      if(!['string','number'].includes(typeof raw)||String(raw).length>100)throw new Error('invalid_fields');
      result[key]=String(raw);
    }
  }
  if(message.catalog===true){
    if(!['all','mine','venda','locacao','opportunity'].includes(message.facet)||!['asc','desc'].includes(message.direction)||typeof message.order!=='string'||message.order.length>30||!Number.isInteger(message.page)||message.page<1||message.page>10000)throw new Error('invalid_fields');
    Object.assign(result,{catalog:true,facet:message.facet,order:message.order,direction:message.direction,page:message.page,include_options:message.includeOptions===true});
  }
  return result;
}
