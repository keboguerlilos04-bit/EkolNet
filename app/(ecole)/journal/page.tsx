import { notFound } from "next/navigation";
import { getSchoolContext, isAdminLevel } from "@/lib/access";
import { getMessages, MODULE_LABELS, SENSITIVE_LABELS, type Lang } from "@/lib/i18n";
import { createClient } from "@/lib/supabase/server";

type LogRow = {
  id: number;
  actor_id: string | null;
  action: string;
  target_member_id: string | null;
  details: { old?: Record<string, unknown> | null; new?: Record<string, unknown> | null; reason?: string };
  created_at: string;
};

/** Phrase lisible pour une ligne du journal. */
function describe(row: LogRow, lang: Lang, roleNames: Map<string, string>): string {
  const n = row.details.new ?? {};
  const o = row.details.old ?? {};
  const fr = lang === "fr";
  const lvl = (v: unknown) => (v === "admin" ? "Admin" : v === "owner" ? (fr ? "Propriétaire" : "Pwopriyetè") : fr ? "Employé" : "Anplwaye");
  const acc = (v: unknown) => [fr ? "Pas d'accès" : "Pa wè", fr ? "Voir" : "Wè", fr ? "Modifier" : "Modifye"][Number(v)] ?? "—";
  switch (row.action) {
    case "member_roles.insert": return (fr ? "Rôle ajouté : " : "Wòl ajoute: ") + (roleNames.get(String(n.role_id)) ?? "—");
    case "member_roles.delete": return (fr ? "Rôle retiré : " : "Wòl retire: ") + (roleNames.get(String(o.role_id)) ?? "—");
    case "member_overrides.insert":
    case "member_overrides.update": return `${MODULE_LABELS[lang][String(n.module)] ?? n.module} : ${acc(n.access)}`;
    case "member_overrides.delete": return `${MODULE_LABELS[lang][String(o.module)] ?? o.module} : ${fr ? "comme ses rôles" : "jan wòl li yo"}`;
    case "member_sensitive.insert": return "✓ " + (SENSITIVE_LABELS[lang][String(n.perm)] ?? n.perm);
    case "member_sensitive.delete": return "✕ " + (SENSITIVE_LABELS[lang][String(o.perm)] ?? o.perm);
    case "school_members.insert": return fr ? "Ajouté à l'équipe" : "Ajoute nan ekip la";
    case "school_members.update":
      if (o.level !== n.level) return `${lvl(o.level)} → ${lvl(n.level)}`;
      return n.active ? (fr ? "Compte réactivé" : "Kont lan reaktive") : (fr ? "Compte désactivé" : "Kont lan dezaktive");
    case "bulletin_blocks.insert": return fr ? "Bulletin bloqué" : "Kanè bloke";
    case "bulletin_blocks.delete": return fr ? "Bulletin débloqué" : "Kanè debloke";
    case "ownership.transfer": return fr ? "Propriété transférée" : "Pwopriyete transfere";
    default: return row.action;
  }
}

export default async function AuditLogPage() {
  const ctx = (await getSchoolContext())!;
  if (!isAdminLevel(ctx)) notFound();
  const { lang, t } = await getMessages();
  const supabase = await createClient();
  const schoolId = ctx.school!.id;

  const [{ data: rows }, { data: members }, { data: roles }] = await Promise.all([
    supabase.from("audit_log").select("id, actor_id, action, target_member_id, details, created_at")
      .eq("school_id", schoolId).order("created_at", { ascending: false }).limit(200),
    supabase.from("school_members").select("id, user_id, full_name").eq("school_id", schoolId),
    supabase.from("roles").select("id, name").eq("school_id", schoolId),
  ]);

  const byUser = new Map((members ?? []).map((m) => [m.user_id as string, m.full_name as string]));
  const byMember = new Map((members ?? []).map((m) => [m.id as string, m.full_name as string]));
  const roleNames = new Map((roles ?? []).map((r) => [r.id as string, r.name as string]));
  const fmt = new Intl.DateTimeFormat(lang === "fr" ? "fr-FR" : "fr-HT", { dateStyle: "medium", timeStyle: "short" });

  return (
    <>
      <h1 style={{ fontSize: 22, margin: 0 }}>{t.auditLog}</h1>
      <div className="card">
        {(rows ?? []).length === 0 ? (
          <p className="muted" style={{ margin: 0 }}>{t.noLog}</p>
        ) : (
          <div className="tbl">
            <table>
              <thead><tr><th>{t.when}</th><th>{t.who}</th><th>{t.action}</th><th>{t.forWhom}</th></tr></thead>
              <tbody>
                {((rows ?? []) as LogRow[]).map((r) => (
                  <tr key={r.id}>
                    <td className="num muted" style={{ whiteSpace: "nowrap" }}>{fmt.format(new Date(r.created_at))}</td>
                    <td>{(r.actor_id && byUser.get(r.actor_id)) ?? "—"}</td>
                    <td>{describe(r, lang, roleNames)}</td>
                    <td>{(r.target_member_id && byMember.get(r.target_member_id)) ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="note" style={{ margin: "14px 0 0" }}>{t.logLocked}</p>
      </div>
    </>
  );
}
