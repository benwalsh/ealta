import { useRef } from 'react'
import { useLang } from '../lang'

// Walk the diary a completed day at a time, bounded to [first detection … yesterday]. Prev/next
// arrows for the common step, plus a native date field to jump. Emits an ISO date string; the
// Journal tab holds it and refetches. Dates compare lexically (ISO), so no Date maths is needed
// for the bounds; the arrows shift by a day via local Date parts (no UTC drift).
function addDays(iso: string, days: number): string {
  const d = new Date(`${iso}T00:00:00`)
  d.setDate(d.getDate() + days)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function CalendarPicker({
  date,
  dateLabel,
  available,
  onChange,
}: {
  date: string | null
  // The formatted, human date the picker reads as ("Monday, 20 July, 2026") — the entry has no
  // separate dateline, so the control itself is the date.
  dateLabel: string
  available: { first: string | null; last: string }
  onChange: (date: string) => void
}) {
  const { t } = useLang()
  const inputRef = useRef<HTMLInputElement>(null)
  const { first, last } = available
  if (!date || !first) return null

  const atStart = date <= first
  const atEnd = date >= last
  const step = (days: number) => {
    const next = addDays(date, days)
    if (next >= first && next <= last) onChange(next)
  }
  // The native date field is laid invisibly over the label; clicking the date opens the browser's
  // own calendar (showPicker) while the reader only ever sees the formatted label.
  const openPicker = () => {
    const el = inputRef.current
    if (!el) return
    if (typeof el.showPicker === 'function') el.showPicker()
    else el.focus()
  }

  return (
    <div className="cal" role="group" aria-label={t('Choose a day', 'Roghnaigh lá')}>
      <button
        className="cal-arrow"
        onClick={() => step(-1)}
        disabled={atStart}
        aria-label={t('Previous day', 'Lá roimhe')}
      >
        <i className="ti ti-chevron-left" aria-hidden="true" />
      </button>
      <div className="cal-date">
        <button type="button" className="cal-date-btn" onClick={openPicker}>
          {dateLabel}
        </button>
        <input
          ref={inputRef}
          className="cal-date-native"
          type="date"
          value={date}
          min={first}
          max={last}
          tabIndex={-1}
          aria-label={t('Choose a day', 'Roghnaigh lá')}
          onChange={(e) => e.target.value && onChange(e.target.value)}
        />
      </div>
      <button
        className="cal-arrow"
        onClick={() => step(1)}
        disabled={atEnd}
        aria-label={t('Next day', 'An lá dár gcionn')}
      >
        <i className="ti ti-chevron-right" aria-hidden="true" />
      </button>
    </div>
  )
}
