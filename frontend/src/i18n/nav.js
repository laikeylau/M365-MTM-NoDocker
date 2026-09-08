import { useCallback, useMemo } from "react";
import { useTranslation } from "react-i18next";

import i18next from "./index";

/**
 * Translate a navigation title (English source string) into the active
 * language. Falls back to the input unchanged when no translation exists,
 * which keeps untranslated entries usable in every language.
 *
 * Safe to call outside React (event handlers, non-component helpers), but
 * components that call it directly should prefer `useNavTitle()` so they
 * re-render when the language changes.
 */
export const tNavTitle = (title) => {
  if (typeof title !== "string" || title.length === 0) return title;
  return i18next.t(title, { ns: "nav", defaultValue: title });
};

/**
 * Hook variant that subscribes the calling component to language changes so
 * the side nav / breadcrumb re-render when the user switches language.
 */
export const useNavTitle = () => {
  const { i18n } = useTranslation();
  return useCallback(
    (title) => {
      if (typeof title !== "string" || title.length === 0) return title;
      return i18n.t(title, { ns: "nav", defaultValue: title });
    },
    [i18n]
  );
};

const translateItemsTree = (items, translate) =>
  (items ?? []).map((item) => ({
    ...item,
    title: translate(item.title),
    ...(item.items ? { items: translateItemsTree(item.items, translate) } : {}),
  }));

/**
 * Deep-translate a navigation items tree (config.js shape) while preserving
 * every other property (icon, path, permissions, ...). Memoized on the input
 * tree and the active language.
 */
export const useTranslatedNavItems = (items) => {
  const translate = useNavTitle();
  return useMemo(() => translateItemsTree(items, translate), [items, translate]);
};
