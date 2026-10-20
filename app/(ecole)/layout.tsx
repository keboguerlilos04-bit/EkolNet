import Link from "next/link";
import { redirect } from "next/navigation";
import { signOut } from "@/app/actions";
import { LangSwitch } from "@/components/LangSwitch";
import { NavLinks, type NavGroup } from "@/components/NavLinks";
import { canSee, getSchoolContext, isAdminLevel } from "@/lib/access";
import { getMessages } from "@/lib/i18n";

export default async function SchoolLayout({ children }: { children: React.ReactNode }) {
  const ctx = await getSchoolContext();
  if (!ctx) redirect("/connexion");
  const { lang, t } = await getMessages();

  if (!ctx.school || !ctx.member) {
    return (
      <main className="auth">
        <div className="card">
          <h1>{t.noMembershipTitle}</h1>
          <p className="muted">{t.noMembershipText}</p>
          <div className="row" style={{ marginTop: 16 }}>
            <Link className="btn p" href="/creer-ecole">{t.createSchoolLink}</Link>
            <form action={signOut}>
              <button className="btn" type="submit">{t.signOut}</button>
            </form>
          </div>
        </div>
      </main>
    );
  }

  // Le menu ne montre que ce que la personne peut voir ; la base de données
  // refuse de toute façon ce qui n'est pas permis.
  const item = (module: string | null, href: string, label: string) =>
    module === null || canSee(ctx, module) ? [{ href, label }] : [];
  const groups: NavGroup[] = [
    { label: t.navSchool, items: [
      ...item("dashboard", "/tableau-de-bord", t.dashboard),
      ...item("students", "/eleves", t.students),
      ...item("enrollment", "/inscription", t.enrollment),
    ] },
    { label: t.navAcademic, items: [
      ...item("grades", "/notes", t.grades),
      ...item("attendance", "/presences", t.attendance),
      ...item("homework", "/devoirs", t.homework),
      ...item("grades", "/bulletins", t.bulletins),
    ] },
    { label: t.navMoney, items: [...item("finance", "/caisse", t.finance)] },
    { label: t.navAdmin, items: isAdminLevel(ctx)
      ? [{ href: "/equipe", label: t.team }, { href: "/journal", label: t.auditLog }]
      : [] },
  ].filter((g) => g.items.length > 0);

  const levelLabel = ctx.member.level === "owner" ? t.owner : ctx.member.level === "admin" ? t.admin : ctx.member.title ?? t.employee;
  const initials = ctx.member.fullName.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join("").toUpperCase();

  return (
    <div className="app">
      <aside className="rail">
        <Link className="brand" href="/tableau-de-bord"><b>E</b>{t.appName}</Link>
        <NavLinks groups={groups} />
        <div className="railfoot">{ctx.school.name}<br />{t.schoolCode} : {ctx.school.code}</div>
      </aside>
      <div className="main">
        <header className="top">
          <span className="sp" />
          <LangSwitch lang={lang} t={t} />
          <div className="who">
            <div className="av" style={{ background: "var(--amber)", color: "var(--navy)" }}>{initials}</div>
            <div style={{ fontSize: 13.5, lineHeight: 1.25 }}>
              <b style={{ fontWeight: 600 }}>{ctx.member.fullName}</b>
              <small>{levelLabel}</small>
            </div>
          </div>
          <form action={signOut}>
            <button className="btn sm" type="submit">{t.signOut}</button>
          </form>
        </header>
        <div className="content">{children}</div>
      </div>
    </div>
  );
}
