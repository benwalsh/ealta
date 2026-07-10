// The time-window control, in the mono broadsheet voice. It lives next to what it
// visibly changes — the activity line on Birds, the leaderboard on Stats — rather
// than up in the masthead where it read as chrome.
export function WindowPicker({
  windows,
  value,
  onChange,
}: {
  windows: [string, number][]
  value: number
  onChange: (hours: number) => void
}) {
  return (
    <div className="ed-window" role="group" aria-label="Time window">
      {windows.map(([label, hours]) => (
        <button
          key={hours}
          className={`ed-win-opt${value === hours ? ' is-on' : ''}`}
          aria-pressed={value === hours}
          onClick={() => onChange(hours)}
        >
          {label}
        </button>
      ))}
    </div>
  )
}
