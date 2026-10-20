import { setLang } from "@/app/actions";
import type { Lang, Messages } from "@/lib/i18n";

export function LangSwitch({ lang, t }: { lang: Lang; t: Messages }) {
  return (
    <form action={setLang} className="langs" aria-label="Langue / Lang">
      <button type="submit" name="lang" value="fr" aria-pressed={lang === "fr"}>
        {t.langFr}
      </button>
      <button type="submit" name="lang" value="ht" aria-pressed={lang === "ht"}>
        {t.langHt}
      </button>
    </form>
  );
}
