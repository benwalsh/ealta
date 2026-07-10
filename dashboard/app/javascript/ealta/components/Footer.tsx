import { useLang } from '../lang'

// The place and the name are the instance's own — from config via the bootstrap, never
// hard-coded. Absent (unconfigured) → just the station line, no place. The lat/lon sits
// with the place here (the almanac row no longer shows either).
export function Footer({
  place,
  siteName,
}: {
  place: { en: string; ga: string; coords: string | null } | null
  siteName: string
}) {
  const { t, lang } = useLang()
  const here = place ? (lang === 'ga' ? place.ga : place.en) : null
  return (
    <footer className="ed-foot">
      <span>{t(`${siteName} · Listening Station`, `${siteName} · Stáisiún Éisteachta`)}</span>
      {here && <span className="dot">·</span>}
      {here && (
        <span>
          {here}
          {place?.coords && <span className="foot-coords"> · {place.coords}</span>}
        </span>
      )}
    </footer>
  )
}
