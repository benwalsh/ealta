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
export interface SparkGap {
  x0: number
  x1: number
  label: Bilingual
  short: Bilingual
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
    busiest: { sci: string; en: string; ga: string | null; count: number } | null
  }
  summary: { en: string[]; ga: string[] }
  source: 'llm' | 'facts' | 'template' | null
  sources: { host: string; url: string }[]
  // The day's 24h activity curve, rendered stilled (greyscale) — the finished day's shape.
  sparkline: SparkPaths | null
  // The day in Irish tradition — a curated feast/quarter-day or the Celtic season.
  day_lore: { title: Bilingual; gloss: Bilingual; kind: string } | null
  notable: NotableGroups
  // The day's closing quotes, each set apart with its credit: the curated literary
  // lore (poem/tale) and any sourced folklore (dúchas etc.) — never woven into prose.
  quotes: {
    kind: 'poem' | 'tale' | 'folklore'
    text: string
    text_ga?: string | null
    attribution: string | null
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
  url: string
}
export type EnrichmentKind = 'fact' | 'regional_note' | 'folklore' | 'station_reading'
export interface EnrichmentBlock {
  type: EnrichmentKind
  text: string
  text_ga: string | null
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
