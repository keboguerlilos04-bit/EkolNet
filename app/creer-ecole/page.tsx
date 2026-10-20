import Link from "next/link";
import { redirect } from "next/navigation";
import { LangSwitch } from "@/components/LangSwitch";
import { getSchoolContext } from "@/lib/access";
import { getMessages } from "@/lib/i18n";
import { CreateSchoolForm } from "./CreateSchoolForm";

export default async function CreateSchoolPage() {
  const { lang, t } = await getMessages();
  const ctx = await getSchoolContext();
  if (ctx?.school) redirect("/tableau-de-bord");

  return (
    <main className="auth">
      <div className="card">
        <div className="row">
          <span className="brand" style={{ color: "var(--fg)", padding: 0 }}>
            <b>E</b>
            {t.appName}
          </span>
          <span className="sp" />
          <LangSwitch lang={lang} t={t} />
        </div>
        <h1>{t.createSchoolTitle}</h1>
        <p className="muted" style={{ margin: 0 }}>{t.createSchoolIntro}</p>
        <CreateSchoolForm t={t} needsAccount={!ctx} />
        {!ctx && (
          <p className="faint" style={{ marginTop: 18 }}>
            {t.alreadyAccount} <Link href="/connexion">{t.signIn}</Link>
          </p>
        )}
      </div>
    </main>
  );
}
