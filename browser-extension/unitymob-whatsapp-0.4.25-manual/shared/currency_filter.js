// Catalog filters use whole reais, matching the admin currency-mask control.
export function currencyFilterDigits(value) {
  return String(value ?? '').replace(/\D/g, '');
}

export function formatCurrencyFilter(value) {
  const digits = currencyFilterDigits(value);
  return digits === '' ? '' : new Intl.NumberFormat('pt-BR', {
    minimumFractionDigits: 0, maximumFractionDigits: 0
  }).format(Number(digits));
}
