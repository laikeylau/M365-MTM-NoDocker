import i18next from "i18next";
import { initReactI18next } from "react-i18next";

import zhNav from "./locales/zh-CN/nav.json";

export const LANG_STORAGE_KEY = "app.language";
export const FALLBACK_LANGUAGE = "en";

export const SUPPORTED_LANGUAGES = [
  { code: "en", label: "English", shortLabel: "EN" },
  { code: "zh-CN", label: "简体中文", shortLabel: "中" },
];

export const isSupportedLanguage = (lng) =>
  SUPPORTED_LANGUAGES.some((language) => language.code === lng);

export const getStoredLanguage = () => {
  if (typeof window === "undefined") return FALLBACK_LANGUAGE;
  try {
    const stored = window.localStorage.getItem(LANG_STORAGE_KEY);
    if (isSupportedLanguage(stored)) return stored;
  } catch {
    // storage unavailable, fall through to detection
  }
  const navigatorLanguage = typeof navigator !== "undefined" ? navigator.language : "";
  return navigatorLanguage?.toLowerCase().startsWith("zh") ? "zh-CN" : FALLBACK_LANGUAGE;
};

export const setStoredLanguage = (lng) => {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(LANG_STORAGE_KEY, lng);
  } catch {
    // storage unavailable
  }
};

if (!i18next.isInitialized) {
  i18next.use(initReactI18next).init({
    resources: {
      "zh-CN": { nav: zhNav },
    },
    lng: getStoredLanguage(),
    fallbackLng: FALLBACK_LANGUAGE,
    defaultNS: "nav",
    ns: ["nav"],
    // Nav titles are translated by their exact English string, so keys must be
    // treated atomically (titles contain '.' and '/' characters).
    keySeparator: false,
    nsSeparator: false,
    // Missing keys return the key itself, which is the English source string.
    parseMissingKeyHandler: (key) => key,
    interpolation: { escapeValue: false },
    react: { useSuspense: false },
  });

  i18next.on("languageChanged", setStoredLanguage);
}

export default i18next;
