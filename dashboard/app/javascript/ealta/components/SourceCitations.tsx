import { useLang } from '../lang'

// The "Facts & folklore" citation line under a day's narration — one link per distinct
// source PAGE (a Wikipedia/dúchas article, a CELT text), so every bird/topic the note draws
// on is traceable. Shared by the Journal entry (and any future narrated block).

// Friendly names for the citation hosts; anything unlisted shows its bare domain.
const HOST_LABEL: Record<string, string> = {
  'duchas.ie': 'dúchas.ie',
  'www.duchas.ie': 'dúchas.ie',
  'celt.ucc.ie': 'CELT',
  'en.wikipedia.org': 'Wikipedia',
  'ga.wikipedia.org': 'Vicipéid',
  'birdwatchireland.ie': 'BirdWatch Ireland',
  'www.birdwatchireland.ie': 'BirdWatch Ireland',
  'irbc.ie': 'Irish Rare Birds Committee',
  'iwt.ie': 'Irish Wildlife Trust',
  'biodiversityireland.ie': 'Biodiversity Ireland',
  'irishheritagenews.ie': 'Irish Heritage News',
}
const label = (host: string) => HOST_LABEL[host] ?? host.replace(/^www\./, '')

// A readable name for one citation: a Wikipedia/dúchas article's own title (…/wiki/Crop_milk
// → "Crop milk"), else the source's host label.
function sourceName(url: string, host: string): string {
  const wiki = url.match(/\/wiki\/([^?#]+)/)
  if (wiki) return decodeURIComponent(wiki[1]).replace(/_/g, ' ')
  if (/\/cbes\/\d+\/\d+/.test(url)) return 'dúchas story'
  return label(host)
}

// One link per distinct source PAGE (not collapsed to one host). Capped so the line stays a
// quiet citation, not a wall.
function distinctSources(sources: { host: string; url: string }[]) {
  const seen = new Map<string, { name: string; url: string }>()
  for (const s of sources)
    if (!seen.has(s.url)) seen.set(s.url, { name: sourceName(s.url, s.host), url: s.url })
  return [...seen.values()].slice(0, 8)
}

export function SourceCitations({ sources }: { sources: { host: string; url: string }[] }) {
  const { t } = useLang()
  const list = distinctSources(sources ?? [])
  if (!list.length) return null

  return (
    <p className="today-sources">
      <span className="today-sources-label">{t('Facts & folklore', 'Fíricí is béaloideas')}</span>
      {list.map((s) => (
        <a key={s.url} href={s.url} target="_blank" rel="noopener noreferrer">
          {s.name}
        </a>
      ))}
    </p>
  )
}
