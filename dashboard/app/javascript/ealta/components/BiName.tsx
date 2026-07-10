import { useLang } from '../lang'

// A bilingual species name: the current language leads, the other trails as a
// muted gloss (matching the server-rendered lists).
export function BiName({ en, ga }: { en: string; ga: string | null }) {
  const { lang } = useLang()
  const primary = lang === 'ga' && ga ? ga : en
  const gloss = lang === 'ga' ? (ga ? en : null) : ga
  return (
    <span className="ed-row-name">
      {primary}
      {gloss && <span className="ed-gloss">{gloss}</span>}
    </span>
  )
}
