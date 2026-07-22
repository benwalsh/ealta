export type Lang = 'en' | 'ga'
export type Conservation = 'red' | 'amber' | 'green' | null

export interface CurrentUser {
  name: string
  email: string | null
  avatar_url: string | null
  admin: boolean
}

export interface Bootstrap {
  current_user: CurrentUser | null
  ui_lang: Lang
  windows: [string, number][]
  // The station's own place, with a compact lat/lon label for the footer.
  place: { en: string; ga: string; coords: string | null } | null
  // sci_names the signed-in user already follows (seeds the follow checkboxes).
  favourites: string[]
  // What this station calls itself (station.yml: site_name) — the engine names nothing.
  site_name: string
  // The station's mark, streamed from its profile. null when the station ships none.
  assets: { mark: string | null; mark_alt: { en: string; ga: string } }
  // A hard nav to /account or /admin boots the SPA with that side-panel pre-opened.
  open_panel: 'account' | 'admin' | null
}

// The account panel's own data (GET /account.json). The follow LIST isn't here — it
// comes from the FollowProvider (favourites), resolving names against `species`.
export interface SpeciesOption {
  sci: string
  en: string
  ga: string | null
}
export interface Account {
  roundup: boolean
  species: SpeciesOption[]
}

// The admin health panel's data (GET /admin.json). Mirrors AdminHealth.snapshot with
// Times as ISO strings, plus the station-language block for the wall-language control.
export interface AdminHealth {
  listening: {
    freshness: 'fresh' | 'quiet' | 'stale' | 'none'
    last_alive_at: string | null
    last_heard_at: string | null
    last_species: { en: string; ga: string | null } | null
    detections_today: number
    species_today: number
    // False where restarting can't work (no systemctl / unit) — the control is hidden.
    restartable: boolean
  }
  alerts: {
    configured: boolean
    from: string | null
    events_pending: number
  }
  // Where and when the daily letter actually goes out. sends_here is false on the Pi/dev,
  // where not sending is by design rather than a fault.
  // `readers` is how many people the letter reaches — the number a broadcast must be
  // confirmed against, so the last act before sending is reading how many.
  letter: { sends_here: boolean; at: string; zone: string; readers: number }
  backup: { configured: boolean; bucket: string | null; expected: boolean }
  station: {
    language: string
    options: { code: string; name: string }[]
  }
  device: DeviceVitals
}

// What the wall last said about itself (birdnet/vitals.py → /ingest/vitals → DeviceVital).
// Every reading is nullable and null means UNKNOWN, not zero or false: collection on the
// device is best-effort, so a dev box reports mostly nulls and the panel must render that as
// "—" rather than as a healthy-looking figure it invented.
export interface DeviceVitals {
  // 'none' where the station has never reported. 'stale' means the readings below are the last
  // known state rather than the current one — the panel says so out loud, because a device that
  // went dark an hour ago showing healthy values is worse than one showing nothing.
  reporting: 'fresh' | 'stale' | 'none'
  received_at?: string | null
  // Already plain sentences, server-side. Nothing here is ever a raw code.
  warnings?: string[]
  // dirty means someone edited the checkout in place: the running code is no longer any commit.
  version?: { sha: string | null; dirty: boolean | null }
  uptime?: number | null
  // pushed_at is when pixels last reached the glass; ran_at is when the shooter last tried.
  // A recent ran_at with an older pushed_at is healthy (nothing changed); both old is a frozen panel.
  panel?: { pushed_at: string | null; ran_at: string | null; outcome: string | null }
  services?: Record<string, { state: string | null; restarts: number | null }> | null
  litestream?: { at: string | null; error: string | null }
  disk?: { free_mb: number | null; total_mb: number | null }
  cpu_temp_c?: number | null
  power?: { now: boolean | null; since_boot: boolean | null }
  mic_name?: string | null
}

export interface CollageNode {
  cx: number
  cy: number
  r: number
  w: number
  h: number
  image: string | null
  // The plain perched pose, whatever image/flip the collage chose — used by the hits strip.
  perch_image: string | null
  fill: string
  sci: string
  ga: string | null
  en: string
  count: number
  flip: boolean
}
export interface CollageData {
  width: number
  height: number
  species_count: number
  nodes: CollageNode[]
}

export interface Tally {
  sci: string
  en: string
  ga: string | null
  count: number
  last_time: string
  confidence: number
}
export interface LifeEntry {
  sci: string
  en: string
  ga: string | null
  count: number
  today: number
  first_seen: string | null
  last_seen: string | null
  conservation: Conservation
  image: string | null
}

export interface Stats {
  window: number
  summary_cards: {
    species_logged: number
    detections_all_time: number
    days_listening: number
  }
  top_species: Tally[]
  by_period: Period[]
  first_seen: LifeEntry[]
}

export type Sort = 'count' | 'recent' | 'alpha'
export type Scope = 'heard' | 'all'
export interface Directory {
  sort: Sort
  scope: Scope
  species: LifeEntry[]
}
export interface Period {
  label: string
  count: number
}
export interface Moon {
  name: string
  name_ga: string
  illumination: number
  emoji: string
}
export interface Weather {
  temp: number
  text: string
  text_ga: string
  emoji: string
}
export interface Tide {
  type: string
  time: string
  label: string
  label_ga: string
}
export interface Coords {
  lat: number
  lon: number
  place_en: string | null
  place_ga: string | null
  label: string
}
export interface Sun {
  rise: string
  set: string
}
export interface Almanac {
  weather: Weather | null
  tide: Tide | null
  sun: Sun | null
  moon: Moon
  coords: Coords
}
export interface Bilingual {
  en: string
  ga: string
}
// Where the mic was down, as an x-span. Nothing is drawn over it — the curve simply breaks
// there — so the band carries no label any more; `offline` / `mic_hours` say it in words.
export interface SparkGap {
  x0: number
  x1: number
}
export interface SparkPaths {
  path: string
  fill: string
  gaps?: SparkGap[]
  w: number
  h: number
}
export interface Anchor {
  x: number
  en: string
  ga: string
}
export interface FooterItem {
  icon: string
  en: string
  ga: string
  // The moon draws its real phase rather than a fixed glyph: `svg` is the SHADOW (the unlit
  // part), computed in Ruby (MoonPhase#shadow) — ink is dark, so inking the lit part would
  // draw a negative. Absent on every other reading, and null at full moon (nothing dark), when
  // only the outline circle is drawn.
  svg?: string | null
}
export interface Today {
  date_label: Bilingual
  // Pre-shaped, HTML-safe bullet strings (species names already wrapped in <strong>).
  summary: { en: string[]; ga: string[] }
  // 'llm' = model prose; 'facts' = a rich no-model fallback (stored facts/folklore + the
  // day's shape) — both shown; 'template' = the bare deterministic bones, hidden by the card.
  source: 'llm' | 'facts' | 'template'
  // The citations behind the day's bird facts & folklore (dúchas, BirdWatch Ireland, …).
  sources: { host: string; url: string }[]
  total: number
  sparkline: SparkPaths
  anchors: Anchor[]
  footer: FooterItem[]
}
// New & notable — the day's newsworthy birds, grouped by kind. A follow ('species') is
// personal, not news, so it never appears here; "your favourites" is added client-side.
export type NotableKind = 'rarity' | 'first_ever' | 'seasonal'
export interface NotableItem {
  sci: string
  en: string
  ga: string | null
}
export interface NotableGroups {
  rarity: NotableItem[]
  first_ever: NotableItem[]
  seasonal: NotableItem[]
}

// A completed day's frozen diary entry (the Journal tab). Figures + notable are recomputed
// from the immutable detections; the narration is frozen once. `poem` arrives in a later phase.
export interface JournalDay {
  date: string | null
  date_label: Bilingual
  figures: {
    species: number
    detections: number
    // The day's listening time in seconds (mic-up hours, gaps removed). null when coverage is
    // unknown — an old day past heartbeat retention — so the stats line drops the duration.
    duration_seconds: number | null
    busiest: { sci: string; en: string; ga: string | null; count: number } | null
  }
  // The day's birds, last-heard first — Live's "Recently heard" locked to this day. Same shape,
  // same component; capped like Live's, so `heard.length` is not the day's species total (that
  // is `figures.species`).
  heard: Tally[]
  summary: { en: string[]; ga: string[] }
  source: 'llm' | 'facts' | 'template' | null
  sources: { host: string; url: string }[]
  // The keeper's own line for the day, set apart from the narration. The letter carries the
  // same note — they are the same words. null on almost every day.
  note: string | null
  // The day's 24h activity curve, rendered stilled (greyscale) — the finished day's shape.
  // Hours the mic was down are shown by absence: the line breaks, and a wholly uncovered day
  // draws no path at all.
  sparkline: SparkPaths | null
  // True when the station was down for most of the day — a zero-detection day reads as offline,
  // not as a genuinely quiet one.
  offline: boolean
  // How many of the day's 24 hours the mic was actually listening (heartbeat or a detection proves
  // the hour live). Lets a zero-detection day say how long it listened rather than blur silence with
  // a dead mic. null when coverage is unknown (an old day past heartbeat retention).
  mic_hours: number | null
  // The day in Irish tradition — a curated feast/quarter-day or the Celtic season, with an optional
  // curated deep dive (a longer bilingual passage + citations) when the station supplies one.
  day_lore: {
    title: Bilingual
    gloss: Bilingual
    kind: string
    lore: Bilingual | null
    // The RICH layer: a curated custom/belief/legend/tale fixed to this day (day_lore.yml). Shown
    // in place of the felire_lore floor when present. null on the many days with no curated lore.
    day: {
      kind: string | null
      title: string | null
      text: string | null
      quote: string | null
      note: string | null
      credit: string | null
    } | null
    // The day's saint(s) and verse from the curated calendar (Martyrology of Óengus) — the
    // narrative under the féilire name. `text` is the line to show (gloss, or the quatrain where
    // that's all a day has); `verse` sets it in voice-italic when it's a promoted quatrain.
    // quatrain_ga is only ever set once a fluent reader has verified it. null on a source-gap day.
    narrative: {
      saints: string[]
      text: string
      verse: boolean
      quatrain_ga: string | null
      note: string | null
      credit: string | null
    } | null
    sources: { host: string; url: string }[]
  } | null
  // A rotating local-colour story from the station's own ground (place_lore.yml) — the coast's
  // standing character, and what carries a birdless winter day. null when the station ships none.
  place: {
    place: string
    kind: string | null
    title: string | null
    text: string | null
    quote: string | null
    narrator: string | null
    note: string | null
    credit: string | null
  } | null
  notable: NotableGroups
  // The day's closing quotes, each set apart with its credit: the curated literary lore
  // (poem/legend/belief/tale) and any sourced folklore (dúchas etc.) — never woven into prose.
  quotes: {
    kind: 'poem' | 'legend' | 'belief' | 'tale' | 'folklore'
    // Curated literary lore carries more than a scraped passage: an optional title, a set-apart
    // verse `quote` (inside a prose entry, or the whole of a verse-only one), a context `note`,
    // and a composed book `credit`. All optional — web folklore has none of them.
    title?: string | null
    // The main body: prose or verse. null on a verse-only entry (its verse is in `quote`).
    text: string | null
    text_ga?: string | null
    quote?: string | null
    note?: string | null
    credit?: string | null
    attribution: string | null
    // The full citation when there is one (dúchas carries rights-holder + licence deed + collector),
    // so the coda can link the reference and the licence rather than show a bare string.
    source?: EnrichmentSource | null
    sci: string
    en: string
    ga: string | null
  }[]
  available: { first: string | null; last: string }
}

export interface Overview {
  window: number
  collage: CollageData
  numbers: {
    species_today: number
    detections_today: number
    detections_all_time: number
  }
  // The selected window's headline figures for the stats line above Recently heard. duration is
  // the mic's listening time across the window (gaps removed), null for the "all time" span.
  stats: {
    detections: number
    species: number
    duration_seconds: number | null
  }
  top: Tally[]
  recent: Tally[]
  periods: Period[]
  almanac: Almanac
  today: Today
  notable: NotableGroups
  // Whether the listening loop is alive (heartbeat / recent detection) — the New &
  // notable status line. See AdminHealth.status.
  status: 'listening' | 'offline'
}

export interface EnrichmentSource {
  host: string | null
  // null for the station's own seed folklore, which cites an attribution rather than a link.
  url: string | null
  // Present on a dúchas (Schools' Collection) citation: the rights-holder, the licence and its
  // deed link, and the collector who recorded the lore — so we render the exact attribution its
  // CC BY-NC 4.0 terms require. Absent on literary/plain credits.
  holder?: string | null
  licence?: string | null
  licence_url?: string | null
  collector?: string | null
}
export type EnrichmentKind = 'fact' | 'regional_note' | 'folklore' | 'station_reading'
export interface EnrichmentBlock {
  type: EnrichmentKind
  // null on a verse-only curated entry (its verse lives in `quote`).
  text: string | null
  text_ga: string | null
  // Curated literary lore only (bird_lore.yml): a title, a set-apart verse, a context note, and a
  // composed book credit. All absent on scraped web blocks.
  title?: string | null
  quote?: string | null
  note?: string | null
  credit?: string | null
  sources: EnrichmentSource[]
}
export interface Enrichment {
  date: string
  blocks: EnrichmentBlock[]
}

export interface SpeciesDetail {
  sci: string
  en: string
  ga: string | null
  all_time: number
  today: number
  first_seen: string | null
  conservation: { status: Conservation; name: string | null; note: string | null }
  illustrations: { label: string; url: string }[]
  description: string | null
  description_ga: string | null
  song: string | null
  recent: { at: string | null; confidence: number }[]
  enrichment: Enrichment | null
}

export type Tab = 'live' | 'journal' | 'stats' | 'directory'
