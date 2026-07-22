import { useEffect, useState } from 'react'
import { useSpecies } from '../api'
import { useLang } from '../lang'
import { useFollow } from '../favourites'
import { FollowButton } from './FollowButton'
import { AudioBar } from './AudioBar'
import { LoreCredit } from './LoreCredit'
import { ago, stamp } from '../time'
import type { Enrichment, EnrichmentBlock } from '../types'

function csrf(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ''
}

// The printer's-mark label for each block type, bilingual.
function loreLabel(type: EnrichmentBlock['type'], t: (en: string, ga?: string) => string): string {
  switch (type) {
    case 'folklore':
      return t('Folklore', 'Béaloideas')
    case 'regional_note':
      return t('In Ireland', 'In Éirinn')
    case 'station_reading':
      return t('At the station', 'Ag an stáisiún')
    default:
      return t('Fact', 'Fíric')
  }
}

// One enrichment block, verbatim from the bundle, with its citations as quiet host
// links — the card renders what Ruby sourced, it never re-derives. Shows the Irish
// rendering in GA when there is one, falling back to English.
function Lore({
  kind,
  block,
  tone,
  ga,
}: {
  kind: string
  block: EnrichmentBlock
  tone: string
  ga: boolean
}) {
  const body = ga && block.text_ga ? block.text_ga : block.text
  return (
    <div className={`modal-lore-item ${tone}`}>
      <span className="modal-lore-k">{kind}</span>
      {block.title && <span className="modal-lore-title">{block.title}</span>}
      {body && <span className="modal-lore-text">{body}</span>}
      {block.quote && <span className="modal-lore-verse">{block.quote}</span>}
      {block.note && <span className="modal-lore-note">{block.note}</span>}
      {/* A curated entry composes its own book credit; a scraped block links its host source(s). */}
      {block.credit ? (
        <span className="modal-lore-credit">{block.credit}</span>
      ) : block.sources.length > 0 ? (
        <span className="modal-lore-src">
          {block.sources.map((s, i) => (
            <LoreCredit key={i} source={s} />
          ))}
        </span>
      ) : null}
    </div>
  )
}

// The species-detail overlay. Reuses the .modal-* design-system classes (loaded
// via pipeline/application.css); data from /api/species/:sci. Header carries the
// follow checkbox (left) and the EN|GA toggle + close (right); the panel closes
// with the station's own signature.
export function SpeciesModal({ sci, onClose }: { sci: string; onClose: () => void }) {
  const { data } = useSpecies(sci)
  const { lang, setLang, t } = useLang()
  const { enabled: signedIn } = useFollow()
  // On-demand look-up result, kept locally so a fetch shows without refetching the card.
  const [looked, setLooked] = useState<Enrichment | null>(null)
  const [looking, setLooking] = useState(false)
  const [lookFailed, setLookFailed] = useState(false)

  // Reset the look-up when the card switches to a different bird (same component).
  useEffect(() => {
    setLooked(null)
    setLooking(false)
    setLookFailed(false)
  }, [sci])

  useEffect(() => {
    const onEsc = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    document.addEventListener('keydown', onEsc)
    document.body.classList.add('modal-open')
    return () => {
      document.removeEventListener('keydown', onEsc)
      document.body.classList.remove('modal-open')
    }
  }, [onClose])

  // Ask the server to source this bird's facts & folklore now (authed), then show them.
  const lookUp = () => {
    setLooking(true)
    setLookFailed(false)
    fetch(`/species/${encodeURIComponent(sci)}/enrichment`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': csrf() },
    })
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((j) => (j.enrichment ? setLooked(j.enrichment) : setLookFailed(true)))
      .catch(() => setLookFailed(true))
      .finally(() => setLooking(false))
  }

  const name = data ? (lang === 'ga' && data.ga ? data.ga : data.en) : ''
  // The other language, shown as the subtitle (Irish under English, or vice versa).
  const subtitle = data ? (lang === 'ga' ? data.en : data.ga) : null
  const desc = data ? (lang === 'ga' ? data.description_ga || data.description : data.description) : null
  const cons = data?.conservation
  // Folklore only. The bundle also carries `fact` / `regional_note` blocks, but those are raw
  // material for the narrated day — the Journal and the letter turn them into prose — not
  // something to list at the reader as cited bullets. Here the description above already says
  // what the bird is; what earns its place after it is the folklore.
  const enr = data?.enrichment ?? looked
  const folk = enr?.blocks.filter((b) => b.type === 'folklore') ?? []

  return (
    <div id="detail-modal" className="is-open">
      <div className="modal-backdrop" onClick={onClose} />
      <article className="modal-card">
        {data && (
          <>
            <div className="modal-head">
              <FollowButton sci={data.sci} variant="full" />
              <div className="modal-head-right">
                <div className="ed-lang" role="group" aria-label="Language">
                  <button
                    className={`ed-lang-opt${lang === 'en' ? ' is-on' : ''}`}
                    onClick={() => setLang('en')}
                  >
                    EN
                  </button>
                  <button
                    className={`ed-lang-opt${lang === 'ga' ? ' is-on' : ''}`}
                    onClick={() => setLang('ga')}
                  >
                    GA
                  </button>
                </div>
                <button className="modal-close" aria-label="close" onClick={onClose}>
                  ×
                </button>
              </div>
            </div>

            <div className="modal-grid">
              <div className="modal-img">
                {data.illustrations.map((img) => (
                  <img key={img.label} src={img.url} alt={`${data.en} (${img.label})`} loading="eager" />
                ))}
              </div>
              <div className="modal-info">
                {cons?.status && (
                  <div className={`cons-line ${cons.status}`}>
                    <span className={`cons-dot ${cons.status}`} />
                    <span className="cons-name">{cons.name} list</span>
                    <span className="cons-note">{cons.note}</span>
                  </div>
                )}
                <h2>{name}</h2>
                {subtitle && subtitle !== name && <p className="common">{subtitle}</p>}
                <p className="sci">{data.sci}</p>
                <div className="modal-stats">
                  <div>
                    <span className="n">{data.all_time.toLocaleString()}</span>
                    <span className="lbl">{t('all time', 'riamh')}</span>
                  </div>
                  <div>
                    <span className="n">{data.today.toLocaleString()}</span>
                    <span className="lbl">{t('today', 'inniu')}</span>
                  </div>
                  <div>
                    <span className="n">{ago(data.first_seen, lang)}</span>
                    <span className="lbl">{t('first heard', 'chéad chloiste')}</span>
                  </div>
                </div>
                {desc && <p className="desc">{desc}</p>}
                {folk.length > 0 ? (
                  <div className="modal-lore">
                    {folk.map((b, i) => (
                      <Lore key={i} kind={loreLabel(b.type, t)} block={b} tone="is-folk" ga={lang === 'ga'} />
                    ))}
                  </div>
                ) : signedIn ? (
                  <button type="button" className="modal-lore-lookup" onClick={lookUp} disabled={looking}>
                    <i className={`ti ${looking ? 'ti-loader' : 'ti-books'}`} aria-hidden="true" />
                    {looking
                      ? t('Looking…', 'Ag cuardach…')
                      : lookFailed
                        ? t('Nothing found — try again', 'Faic fós — féach arís')
                        : t('Look up folklore', 'Cuardaigh béaloideas')}
                  </button>
                ) : null}
                {data.song && (
                  <div className="modal-audio">
                    <span className="modal-audio-label">
                      {t('Listen to the call', 'Éist leis an nglaoch')}
                    </span>
                    <AudioBar src={data.song} />
                  </div>
                )}
              </div>
            </div>

            {/* Detections only for a bird actually heard here — an un-heard species (browsable
                from the "all species" directory, but never recorded) has an empty roll, so the
                table is dropped rather than shown as a bare, zeroed header. */}
            {data.recent.length > 0 && (
              <div className="modal-recordings">
                <div className="rec-head">
                  <h3>{t('Detections', 'Aimsithe')}</h3>
                  <span className="rec-count">
                    {t('most recent', 'is déanaí')} {data.recent.length}
                  </span>
                </div>
                <ol>
                  {data.recent.map((r, i) => (
                    <li key={i}>
                      <span className="rec-when">
                        {ago(r.at, lang)}
                        <small>{stamp(r.at, lang)}</small>
                      </span>
                      <span className="rec-conf">{Math.round(r.confidence * 100)}%</span>
                    </li>
                  ))}
                </ol>
              </div>
            )}
          </>
        )}
      </article>
    </div>
  )
}
