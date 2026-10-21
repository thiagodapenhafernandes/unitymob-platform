import { parsePhoneNumberFromString } from "libphonenumber-max"

export function validatePublicWhatsapp(value) {
  const raw = String(value ?? "").trim()
  const digits = raw.replace(/\D/g, "")
  const invalid = "Informe um WhatsApp válido com DDD, por exemplo (47) 99123-4567."
  if (!/^\+?[\d\s().-]+$/.test(raw)) return { error: invalid }
  if (!raw.startsWith("+") && digits.length > 11) {
    return { error: "Para número de outro país, comece com + e o código do país, por exemplo +351 912 345 678." }
  }
  const number = parsePhoneNumberFromString(raw, { defaultCountry: "BR", extract: false })
  if (!number?.isValid() || number.ext) return { error: invalid }
  if (number.country === "BR") {
    if (number.getType() !== "MOBILE") return { error: "Esse número parece ser de telefone fixo. Informe um número de WhatsApp (celular)." }
    if (!/^\d{2}9\d{8}$/.test(number.nationalNumber) || /(\d)\1{7}$/.test(digits)) return { error: invalid }
  }
  return { e164: number.number }
}
