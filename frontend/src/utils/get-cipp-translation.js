import { CippTranslations } from "../components/CippComponents/CippTranslations";
import i18next from "../i18n";

export const getCippTranslation = (field) => {
  if (field === null || field === undefined) {
    return i18next.t("No data", { ns: "common", defaultValue: "No data" });
  }

  // special translations for extensions
  if (field.startsWith("extension_")) {
    field = field.split("_").pop();
  }
  // special translation for schema extensions
  if (field.startsWith("ext") && field.includes("_")) {
    field = field.split("_").pop();
  }

  // Progressive column-header coverage: route the resolved display name
  // (CippTranslations entry or beautified field name) through the `columns`
  // namespace. Keys are the exact English display strings; missing keys fall
  // back to the input unchanged.
  const displayName =
    CippTranslations[field] ||
    field
      .replace(/([A-Z]+)([A-Z][a-z])/g, "$1 $2")
      .replace(/([a-z])([A-Z])/g, "$1 $2")
      .replace(/(^|\.)(\w)/g, (_, dot, char) => dot + char.toUpperCase())
      .replace(/[_]/g, " ")
      .replace(/\./g, " - ")
      .replace(/([a-z])([A-Z])/g, "$1 $2");

  return i18next.t(displayName, { ns: "columns", defaultValue: displayName });
};
