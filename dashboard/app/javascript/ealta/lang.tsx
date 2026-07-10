import { createContext, useContext, useState, type ReactNode } from 'react'
import type { Lang } from './types'

interface LangCtx {
  lang: Lang
  setLang: (l: Lang) => void
  // Pick the right string for the current language (falls back to English).
  t: (en: string, ga?: string | null) => string
}

const Ctx = createContext<LangCtx>({ lang: 'en', setLang: () => {}, t: (en) => en })

export function LangProvider({ initial, children }: { initial: Lang; children: ReactNode }) {
  const [lang, setLangState] = useState<Lang>(initial)
  const setLang = (l: Lang) => {
    setLangState(l)
    document.documentElement.setAttribute('data-lang', l)
    document.documentElement.setAttribute('lang', l)
    document.cookie = `ui_lang=${l}; path=/; max-age=31536000; samesite=lax`
  }
  const t = (en: string, ga?: string | null) => (lang === 'ga' && ga ? ga : en)
  return <Ctx.Provider value={{ lang, setLang, t }}>{children}</Ctx.Provider>
}

export const useLang = () => useContext(Ctx)
