import { useRef, useState } from 'react'

// A borderless inline call player — no native pill, no plate. Bare play/pause
// mark, a hairline seek line with a thin filled lead (the panel's one live thread),
// a running clock, and a mute toggle. Drives a hidden <audio> element.
function clock(s: number): string {
  if (!isFinite(s) || s < 0) s = 0
  const m = Math.floor(s / 60)
  const sec = Math.floor(s % 60)
  return `${m}:${sec.toString().padStart(2, '0')}`
}

export function AudioBar({ src }: { src: string }) {
  const ref = useRef<HTMLAudioElement>(null)
  const [playing, setPlaying] = useState(false)
  const [cur, setCur] = useState(0)
  const [dur, setDur] = useState(0)
  const [muted, setMuted] = useState(false)

  const toggle = () => {
    const a = ref.current
    if (!a) return
    if (a.paused) a.play()
    else a.pause()
  }

  const seek = (e: React.MouseEvent<HTMLDivElement>) => {
    const a = ref.current
    if (!a || !dur) return
    const box = e.currentTarget.getBoundingClientRect()
    const frac = Math.min(1, Math.max(0, (e.clientX - box.left) / box.width))
    a.currentTime = frac * dur
    setCur(a.currentTime)
  }

  const toggleMute = () => {
    const a = ref.current
    if (!a) return
    a.muted = !a.muted
    setMuted(a.muted)
  }

  const pct = dur ? (cur / dur) * 100 : 0

  return (
    <div className="audiobar">
      <audio
        ref={ref}
        src={src}
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
        onEnded={() => setPlaying(false)}
        onTimeUpdate={(e) => setCur(e.currentTarget.currentTime)}
        onLoadedMetadata={(e) => setDur(e.currentTarget.duration)}
      />
      <button type="button" className="audiobar-btn" aria-label={playing ? 'pause' : 'play'} onClick={toggle}>
        {playing ? (
          <svg viewBox="0 0 12 12" aria-hidden="true">
            <rect x="2" y="1.5" width="3" height="9" />
            <rect x="7" y="1.5" width="3" height="9" />
          </svg>
        ) : (
          <svg viewBox="0 0 12 12" aria-hidden="true">
            <path d="M2.5 1.3 10.5 6l-8 4.7z" />
          </svg>
        )}
      </button>
      <div
        className="audiobar-seek"
        role="slider"
        aria-label="seek"
        aria-valuenow={Math.round(pct)}
        onClick={seek}
      >
        <span className="audiobar-track" />
        <span className="audiobar-fill" style={{ width: `${pct}%` }} />
        <span className="audiobar-head" style={{ left: `${pct}%` }} />
      </div>
      <span className="audiobar-time">
        {clock(cur)} / {clock(dur)}
      </span>
      <button
        type="button"
        className="audiobar-mute"
        aria-label={muted ? 'unmute' : 'mute'}
        onClick={toggleMute}
      >
        {muted ? (
          <svg viewBox="0 0 16 16" aria-hidden="true">
            <path d="M2 6h2.5L8 3v10L4.5 10H2z" fill="currentColor" />
            <path d="M11 6l3 3M14 6l-3 3" stroke="currentColor" strokeWidth="1.2" fill="none" />
          </svg>
        ) : (
          <svg viewBox="0 0 16 16" aria-hidden="true">
            <path d="M2 6h2.5L8 3v10L4.5 10H2z" fill="currentColor" />
            <path
              d="M11 5.5a3.4 3.4 0 0 1 0 5M12.7 4a5.6 5.6 0 0 1 0 8"
              stroke="currentColor"
              strokeWidth="1.2"
              fill="none"
            />
          </svg>
        )}
      </button>
    </div>
  )
}
