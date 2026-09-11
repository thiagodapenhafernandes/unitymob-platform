// The existing API returns 20 rows; expose ten at a time without fetching twice.
export function propertyPagination(fetchPage) {
  let cached=null, generation=0;
  return {
    reset(){generation++;cached=null;},
    async load(params){
      const version=generation;
      const page=Math.ceil(params.page/2);
      const result=cached?.page===page?cached.result:await fetchPage({...params,page});
      if(version===generation)cached={page,result};
      const offset=params.page%2===1?0:10;
      return {...result,properties:result.properties.slice(offset,offset+10),more:result.properties.length>offset+10 || result.more,
        filter_options:offset===0?result.filter_options:null};
    }
  };
}
