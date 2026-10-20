import Link from "next/link";
import { notFound } from "next/navigation";
import { getSchoolContext, isAdminLevel, MODULES, SENSITIVE } from "@/lib/access";
import { getMessages, MODULE_LABELS, SENSITIVE_LABELS } from "@/lib/i18n";
import { createClient } from "@/lib/supabase/server";
import { roleDerivedAccess, type Perm } from "@/lib/team";
import { resetMemberOverrides, setMemberActive, setMemberLevel } from "../actions";
import { AccessForm } from "./AccessForm";

export default async function MemberAccessPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const ctx = (await getSchoolContext())!;
  if (!isAdminLevel(ctx)) notFound();
  const { lang, t } = await getMessages();
  const supabase = await createClient();

  const { data: member } = await supabase
    .from("school_members")
    .select("id, full_name, title, level, active, school_id")
    .eq("id", id)
    .eq("school_id", ctx.school!.id)
    .maybeSingle();
  if (!member || member.level === "owner") notFound();

  const [{ data: roles }, { data: memberRoles }, { data: overrides }, { data: sens }, derived] = await Promise.all([
    supabase.from("roles").select("id, name, description").eq("school_id", ctx.school!.id).order("name"),
    supabase.from("member_roles").select("role_id").eq("member_id", id),
    supabase.from("member_overrides").select("module, access, scope").eq("member_id", id),
    supabase.from("member_sensitive").select("perm").eq("member_id", id),
    roleDerivedAccess(id),
  ]);

  const effective: Record<string, Perm> = { ...derived };
  for (const o of (overrides ?? []) as { module: string; access: number; scope: Perm["scope"] }[]) {
    effective[o.module] = { access: o.access, scope: o.scope };
  }

  const isOwner = ctx.member!.level === "owner";
  // Un admin ne modifie pas un autre admin ; le propriétaire peut tout.
  const locked = member.level === "admin" && !isOwner;

  return (
    <>
      <div className="row">
        <Link className="btn sm" href="/equipe">← {t.back}</Link>
      </div>
      <div className="card">
        <div className="row">
          <div className="who">
            <div className="av" style={{ width: 44, height: 44 }}>{member.full_name.split(/\s+/).slice(0, 2).map((w: string) => w[0]).join("").toUpperCase()}</div>
            <div>
              <b style={{ fontSize: 17 }}>{member.full_name}</b>
              <small>{member.title ?? (member.level === "admin" ? t.admin : t.employee)}</small>
            </div>
          </div>
          <span className="sp" />
          <span className={`tag ${member.level === "admin" ? "t-acc" : "t-n"}`}>{member.level === "admin" ? t.admin : t.employee}</span>
          {isOwner && (
            <form action={setMemberLevel}>
              <input type="hidden" name="memberId" value={member.id} />
              <input type="hidden" name="level" value={member.level === "admin" ? "employee" : "admin"} />
              <button className="btn sm" type="submit">{member.level === "admin" ? t.removeAdmin : t.makeAdmin}</button>
            </form>
          )}
          {!locked && (
            <form action={setMemberActive}>
              <input type="hidden" name="memberId" value={member.id} />
              <input type="hidden" name="active" value={member.active ? "false" : "true"} />
              <button className={`btn sm${member.active ? " danger" : ""}`} type="submit">{member.active ? t.deactivate : t.reactivate}</button>
            </form>
          )}
        </div>
      </div>

      {member.level === "admin" && <p className="info" style={{ margin: 0 }}>{t.adminHasAll}</p>}

      <AccessForm
        key={JSON.stringify([effective, memberRoles, sens])}
        t={t}
        memberId={member.id}
        modules={MODULES.map((m) => ({ key: m, label: MODULE_LABELS[lang][m] }))}
        sensitive={SENSITIVE.map((s) => ({ key: s, label: SENSITIVE_LABELS[lang][s] }))}
        roles={roles ?? []}
        memberRoleIds={(memberRoles ?? []).map((r) => r.role_id as string)}
        effective={effective}
        derived={derived}
        sensitiveOn={(sens ?? []).map((s) => s.perm as string)}
        locked={locked}
      />

      {!locked && (overrides ?? []).length > 0 && (
        <form action={resetMemberOverrides}>
          <input type="hidden" name="memberId" value={member.id} />
          <button className="btn sm" type="submit">{t.resetToRoles}</button>
        </form>
      )}
    </>
  );
}
