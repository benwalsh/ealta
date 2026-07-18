import { useQuery } from '@tanstack/react-query'
import type {
  Overview,
  JournalDay,
  SpeciesDetail,
  Stats,
  Directory,
  Sort,
  Scope,
  Account,
  AdminHealth,
} from './types'

async function fetchJson<T>(url: string): Promise<T> {
  const res = await fetch(url, { headers: { Accept: 'application/json' } })
  if (!res.ok) throw new Error(`${res.status} ${url}`)
  return res.json() as Promise<T>
}

export const useOverview = (h?: number) =>
  useQuery<Overview>({
    queryKey: ['overview', h ?? 24],
    queryFn: () => fetchJson(`/api/overview${h ? `?h=${h}` : ''}`),
  })

// The Journal: a completed day's frozen entry. `date` null → yesterday (the default).
export const useJournal = (date: string | null) =>
  useQuery<JournalDay>({
    queryKey: ['journal', date ?? 'yesterday'],
    queryFn: () => fetchJson(`/api/journal${date ? `?date=${date}` : ''}`),
  })

export const useStats = (h?: number) =>
  useQuery<Stats>({
    queryKey: ['stats', h ?? 24],
    queryFn: () => fetchJson(`/api/stats${h ? `?h=${h}` : ''}`),
  })

export const useDirectory = (sort: Sort, scope: Scope) =>
  useQuery<Directory>({
    queryKey: ['directory', sort, scope],
    queryFn: () => fetchJson(`/api/directory?sort=${sort}&scope=${scope}`),
  })

export const useSpecies = (sci: string | null) =>
  useQuery<SpeciesDetail>({
    queryKey: ['species', sci],
    queryFn: () => fetchJson(`/api/species/${encodeURIComponent(sci as string)}`),
    enabled: !!sci,
  })

// The account panel's data — session-authed, so it lives off /api. Fetched only while
// the panel is open (`enabled`); the follow list itself comes from the FollowProvider.
export const useAccount = (enabled: boolean) =>
  useQuery<Account>({
    queryKey: ['account'],
    queryFn: () => fetchJson('/account'),
    enabled,
  })

// The admin health snapshot — session + admin-gated (403 off it). Polls while open so the
// listening dot and figures stay live; admin mutations invalidate ['health'] to refresh.
//
// networkMode 'always': by default react-query PAUSES a failed fetch when it believes the
// browser is offline, leaving the query pending-but-not-fetching with no error — the console
// then wedges (blank, and `refetch` won't fire) until a full reload. The station is often a
// box on the local network, where those online heuristics are unreliable, so always attempt
// the request and let a real failure surface as a real error.
export const useHealth = (enabled: boolean) =>
  useQuery<AdminHealth>({
    queryKey: ['health'],
    queryFn: () => fetchJson('/admin'),
    enabled,
    refetchInterval: 60_000,
    networkMode: 'always',
  })
