import Link from "next/link";
import { notFound } from "next/navigation";
import { getSchoolContext, isAdminLevel } from "@/lib/access";
import { getMessages } from "@/lib/i18n";
import { createClient } from "@/lib/supabase/server";
import { AddEmployeeForm } from "./AddEmployeeForm";

type MemberRow = {
  id: string;
  full_name: string;
  title: string | null;
  level: "owner" | "admin" | "employee";
  active: boolean;
  member_roles: { role: { name: string } | null }[];
  member_overrides: { module: string }[];
};

export default async function TeamPage() {
  const ctx = (await getSchoolContext())!;
  if (!isAdminLevel(ctx)) notFound();
  const { t } = await getMessages();
  const supabase = await createClient();
  const schoolId = ctx.school!.id;

  const [{ data: members }, { data: roles }] = await Promise.all([
    supabase
      .from("school_members")
      .select("id, full_name, title, level, active, member_roles(role:roles(name)), member_overrides(module)")
      .eq("school_id", schoolId)
      .order("level")
      .order("full_name"),
    supabase.from("roles").select("id, name").eq("school_id", schoolId).order("name"),
  ]);

  const levelTag = { owner: ["t-v", t.owner], admin: ["t-acc", t.admin], employee: ["t-n", t.employee] } as const;

  return (
    <>
      <h1 style={{ fontSize: 22, margin: 0 }}>{t.teamTitle}</h1>
      <p className="info" style={{ margin: 0 }}>{t.onlyOwnerAdmins}</p>
      <div className="card">
        <div className="tbl">
          <table>
            <thead>
              <tr><th>{t.fullName}</th><th>{t.rolesOf}</th><th>{t.level}</th><th>{t.active}</th><th /></tr>
            </thead>
            <tbody>
              {((members ?? []) as unknown as MemberRow[]).map((m) => {
                const [cls, label] = levelTag[m.level];
                return (
                  <tr key={m.id} style={m.active ? undefined : { opacity: 0.55 }}>
                    <td>
                      <div className="who">
                        <div className="av">{m.full_name.split(/\s+/).slice(0, 2).map((w) => w[0]).join("").toUpperCase()}</div>
                        <div><b style={{ fontWeight: 600 }}>{m.full_name}</b><small>{m.title}</small></div>
                      </div>
                    </td>
                    <td>
                      {m.member_roles.map((r, i) => r.role && <span key={i} className="tag t-n" style={{ marginRight: 4 }}>{r.role.name}</span>)}
                      {m.member_overrides.length > 0 && <span className="tag t-warn">+{m.member_overrides.length}</span>}
                    </td>
                    <td><span className={`tag ${cls}`}>{label}</span></td>
                    <td><span className={`tag ${m.active ? "t-ok" : "t-bad"}`}>{m.active ? t.active : t.disabled}</span></td>
                    <td style={{ textAlign: "right" }}>
                      {m.level !== "owner" && <Link className="btn sm" href={`/equipe/${m.id}`}>{t.access}</Link>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
      <AddEmployeeForm t={t} roles={roles ?? []} />
    </>
  );
}
