import { useLang } from '../lang'
import { EnrichmentSource } from '../types'

// One folklore credit, rendered to the exact form its source's licence asks for. A dúchas
// (Schools' Collection) source carries a rights-holder + licence, so it renders the attribution
// CC BY-NC 4.0 requires — the reference linking the human page, the licence linking its deed:
//
//   "The Schools' Collection, Volume 0199, Page 012" by Dúchas © National Folklore Collection,
//   UCD is licensed under CC BY-NC 4.0
//
// plus a quiet "collected by" line crediting the person who recorded the lore. A plain literary
// credit (Yeats, a ninth-century poem) has no holder/licence and renders as a bare link or a
// plain attribution string, exactly as before. Shared by the species modal and the journal coda
// so the wording never drifts between them.
export function LoreCredit({ source }: { source: EnrichmentSource }) {
  const { t } = useLang()
  const { host, url, holder, licence, licence_url, collector } = source
  const ref = url ? (
    <a href={url} target="_blank" rel="noopener noreferrer">
      {host ?? 'source'}
    </a>
  ) : (
    <span>{host}</span>
  )

  // No licence metadata → a plain literary/host credit, untouched.
  if (!holder && !licence) return ref

  return (
    <span className="lore-credit">
      “{ref}” by Dúchas {holder}
      {licence && (
        <>
          {' '}
          {t('is licensed under', 'ceadúnaithe faoi')}{' '}
          {licence_url ? (
            <a href={licence_url} target="_blank" rel="noopener noreferrer">
              {licence}
            </a>
          ) : (
            licence
          )}
        </>
      )}
      {collector && (
        <span className="lore-credit-collector">
          {' · '}
          {t('Collected by', 'Bailithe ag')} {collector}
        </span>
      )}
    </span>
  )
}
