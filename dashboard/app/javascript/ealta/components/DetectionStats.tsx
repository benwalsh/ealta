import { type ReactNode } from 'react'
import { useLang } from '../lang'
import { formatDuration } from '../time'

// The window's headline figures as one quiet mono line above a roll of birds —
// "788 detections · 18 species · 15h". Shared by Live (the selected window) and the Journal
// (one finished day), so the same three numbers head "Recently heard" and "Heard this day" in
// the same voice. `durationSeconds` is listening time with the mic's blind spots removed; null
// (the "all time" span, or an old day past coverage retention) drops that segment.
export function DetectionStats({
  detections,
  species,
  durationSeconds,
}: {
  detections: number
  species: number
  durationSeconds: number | null
}) {
  const { t } = useLang()
  const duration = formatDuration(durationSeconds)

  const segs: ReactNode[] = [
    <>
      <b>{detections.toLocaleString()}</b> {t(detections === 1 ? 'detection' : 'detections', 'aimsithe')}
    </>,
    <>
      <b>{species.toLocaleString()}</b> {t('species', 'speicis')}
    </>,
  ]
  if (duration)
    segs.push(
      <>
        <b>{duration}</b>
      </>,
    )

  return (
    <p className="detstats">
      {segs.map((seg, i) => (
        <span key={i} className="detstats-seg">
          {i > 0 && (
            <span className="detstats-sep" aria-hidden="true">
              ·
            </span>
          )}
          {seg}
        </span>
      ))}
    </p>
  )
}
