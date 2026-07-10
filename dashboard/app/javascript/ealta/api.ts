import { useQuery } from '@tanstack/react-query'
import type { Overview, JournalDay, SpeciesDetail, Stats, Directory, Sort, Scope } from './types'

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
