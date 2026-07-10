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
  available,
  onChange,
}: {
  date: string | null
  available: { first: string | null; last: string }
  onChange: (date: string) => void
}) {
  const { t } = useLang()
  const { first, last } = available
  if (!date || !first) return null

  const atStart = date <= first
  const atEnd = date >= last
  const step = (days: number) => {
    const next = addDays(date, days)
    if (next >= first && next <= last) onChange(next)
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
      <input
        className="cal-date"
        type="date"
        value={date}
        min={first}
        max={last}
        onChange={(e) => e.target.value && onChange(e.target.value)}
      />
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
