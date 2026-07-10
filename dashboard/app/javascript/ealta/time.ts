// Time/date formatting, bilingual. The relative words and month names take a language
// so a date reads the same way in both — "16h ago · 6 Jul" in English, "16u ó shin ·
// 6 Iúil" in Irish. Irish months are the full forms (matching the server's date labels);
// the relative units are the terse single letters n/u/l (nóiméad / uair / lá).
type Lang = 'en' | 'ga'

const EN_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const GA_MONTHS = [
  'Eanáir',
  'Feabhra',
  'Márta',
  'Aibreán',
  'Bealtaine',
  'Meitheamh',
  'Iúil',
  'Lúnasa',
  'Meán Fómhair',
  'Deireadh Fómhair',
  'Samhain',
  'Nollaig',
]

// Detection timestamps arrive as "YYYY-MM-DD HH:MM:SS" (no zone) or ISO8601.
function parse(value: string): number {
  return new Date(value.includes('T') ? value : value.replace(' ', 'T')).getTime()
}

function at(value: string): Date {
  return new Date(value.includes('T') ? value : value.replace(' ', 'T'))
}

// Compact relative time: "now" / "8m ago" / "3h ago" — Irish "anois" / "8n ó shin" /
// "3u ó shin" / "7l ó shin".
export function ago(value: string | null, lang: Lang = 'en'): string {
  if (!value) return '—'
  const secs = (Date.now() - parse(value)) / 1000
  const ga = lang === 'ga'
  if (secs < 60) return ga ? 'anois' : 'now'
  if (secs < 3600) return phrase(Math.floor(secs / 60), 'm', 'n', ga)
  if (secs < 86_400) return phrase(Math.floor(secs / 3600), 'h', 'u', ga)
  return phrase(Math.floor(secs / 86_400), 'd', 'l', ga)
}

function phrase(n: number, enUnit: string, gaUnit: string, ga: boolean): string {
  return ga ? `${n}${gaUnit} ó shin` : `${n}${enUnit} ago`
}

// The bare elapsed magnitude, no "ago" — "now"/"8m"/"3h"/"7d" (Irish "anois"/"8n"/"3u"/
// "7l"). For tight datelines where a following label supplies the sense ("7d first").
export function elapsed(value: string | null, lang: Lang = 'en'): string {
  if (!value) return '—'
  const secs = (Date.now() - parse(value)) / 1000
  const ga = lang === 'ga'
  if (secs < 60) return ga ? 'anois' : 'now'
  if (secs < 3600) return `${Math.floor(secs / 60)}${ga ? 'n' : 'm'}`
  if (secs < 86_400) return `${Math.floor(secs / 3600)}${ga ? 'u' : 'h'}`
  return `${Math.floor(secs / 86_400)}${ga ? 'l' : 'd'}`
}

// "6 Jul 2026" / "6 Iúil 2026".
export function shortDate(value: string | null, lang: Lang = 'en'): string {
  if (!value) return ''
  const d = at(value)
  const months = lang === 'ga' ? GA_MONTHS : EN_MONTHS
  return `${d.getDate()} ${months[d.getMonth()]} ${d.getFullYear()}`
}

// "6 Jul · 22:05" / "6 Iúil · 22:05" for the modal's recordings list.
export function stamp(value: string | null, lang: Lang = 'en'): string {
  if (!value) return ''
  const d = at(value)
  const months = lang === 'ga' ? GA_MONTHS : EN_MONTHS
  const time = d.toLocaleTimeString('en-IE', { hour: '2-digit', minute: '2-digit', hour12: false })
  return `${d.getDate()} ${months[d.getMonth()]} · ${time}`
}
