import Link from "next/link";
import { LangSwitch } from "@/components/LangSwitch";
import { getMessages } from "@/lib/i18n";
import { LoginForm } from "./LoginForm";

export default async function LoginPage() {
  const { lang, t } = await getMessages();
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
        <h1>{t.signInTitle}</h1>
        <p className="muted" style={{ margin: 0 }}>{t.signInIntro}</p>
        <LoginForm t={t} />
        <p className="faint" style={{ marginTop: 18 }}>
          {t.noSchoolYet} <Link href="/creer-ecole">{t.createSchoolLink}</Link>
        </p>
      </div>
    </main>
  );
}
