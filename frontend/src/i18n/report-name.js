import { useCallback } from "react";
import { useTranslation } from "react-i18next";

import i18next from "./index";
import { REPORTS, SERVICES, CATEGORIES } from "../data/report-registry";

/**
 * Report-center name translation (Phase 3 batch 3).
 *
 * The report registry (B1) is the single source of truth: every entry carries
 * `nameEn` / `nameZh`. Instead of duplicating those strings into a locale
 * dictionary, this helper resolves the Chinese name from the registry itself,
 * keyed by the English source string — same "translate at render layer,
 * fall back to English" contract as nav.js.
 */

const buildZhLookup = () => {
  const lookup = new Map();
  for (const service of SERVICES) {
    if (service.nameEn && service.nameZh) lookup.set(service.nameEn, service.nameZh);
  }
  for (const category of Object.values(CATEGORIES)) {
    if (category.nameEn && category.nameZh) lookup.set(category.nameEn, category.nameZh);
  }
  for (const report of REPORTS) {
    if (report.nameEn && report.nameZh) lookup.set(report.nameEn, report.nameZh);
  }
  return lookup;
};

const ZH_BY_NAME_EN = buildZhLookup();

const isZh = (language) => (language ?? "").toLowerCase().startsWith("zh");

/**
 * Translate a report-center name (English source string from the registry)
 * into the active language. Falls back to the input unchanged when the
 * language is English or no registry entry matches.
 *
 * Safe to call outside React; prefer `useReportName()` inside components so
 * they re-render when the language changes.
 */
export const tReportName = (name) => {
  if (typeof name !== "string" || name.length === 0) return name;
  if (!isZh(i18next.language)) return name;
  return ZH_BY_NAME_EN.get(name) ?? name;
};

/**
 * Hook variant that subscribes the calling component to language changes.
 */
export const useReportName = () => {
  const { i18n } = useTranslation();
  return useCallback(
    (name) => {
      if (typeof name !== "string" || name.length === 0) return name;
      if (!isZh(i18n.language)) return name;
      return ZH_BY_NAME_EN.get(name) ?? name;
    },
    [i18n.language]
  );
};

export default useReportName;
