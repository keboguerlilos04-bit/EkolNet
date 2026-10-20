"use server";

import { revalidatePath } from "next/cache";
import { getSchoolContext, isAdminLevel, MODULES, SENSITIVE } from "@/lib/access";
import { createAdminClient, createClient } from "@/lib/supabase/server";
import { roleDerivedAccess, type Perm } from "@/lib/team";

export type TeamState = { error?: string; ok?: string; fields?: Record<string, string> } | null;

async function requireAdmin() {
  const ctx = await getSchoolContext();
  if (!ctx?.school || !isAdminLevel(ctx)) throw new Error("Accès refusé.");
  return ctx;
}

/** La base renvoie un message clair (ex. « Seul le propriétaire… ») : on le montre tel quel. */
function dbMessage(error: { message?: string } | null): string | undefined {
  return error?.message || undefined;
}

export async function addEmployee(_prev: TeamState, formData: FormData): Promise<TeamState> {
  const ctx = await requireAdmin();
  const fields = {
    fullName: String(formData.get("fullName") ?? "").trim(),
    email: String(formData.get("email") ?? "").trim().toLowerCase(),
    phone: String(formData.get("phone") ?? "").trim(),
    title: String(formData.get("title") ?? "").trim(),
  };
  const password = String(formData.get("password") ?? "");
  const roleIds = formData.getAll("roles").map(String);
  if (!fields.fullName || !fields.email || !password) return { error: "required", fields };
  if (password.length < 8) return { error: "passwordTooShort", fields };

  // Seule la création du compte de connexion utilise la clé secrète.
  const admin = createAdminClient();
  const { data: created, error: authError } = await admin.auth.admin.createUser({
    email: fields.email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fields.fullName },
  });
  if (authError || !created.user) {
    return { error: /already|registered|exists/i.test(authError?.message ?? "") ? "emailTaken" : "genericError", fields };
  }

  // Le reste passe par la session de l'admin : les règles de la base s'appliquent.
  const supabase = await createClient();
  const { data: member, error: memberError } = await supabase
    .from("school_members")
    .insert({
      school_id: ctx.school!.id,
      user_id: created.user.id,
      full_name: fields.fullName,
      phone: fields.phone || null,
      title: fields.title || null,
      level: "employee",
    })
    .select("id")
    .single();
  if (memberError || !member) {
    await admin.auth.admin.deleteUser(created.user.id);
    return { error: dbMessage(memberError) ?? "genericError", fields };
  }

  if (roleIds.length) {
    const { error } = await supabase.from("member_roles").insert(roleIds.map((role_id) => ({ member_id: member.id, role_id })));
    if (error) return { error: dbMessage(error), fields };
  }

  revalidatePath("/equipe");
  return { ok: "employeeAdded" };
}

export async function setMemberLevel(formData: FormData) {
  await requireAdmin();
  const memberId = String(formData.get("memberId"));
  const level = formData.get("level") === "admin" ? "admin" : "employee";
  const supabase = await createClient();
  const { error } = await supabase.from("school_members").update({ level }).eq("id", memberId);
  if (error) throw new Error(error.message);
  revalidatePath("/equipe");
  revalidatePath(`/equipe/${memberId}`);
}

export async function setMemberActive(formData: FormData) {
  await requireAdmin();
  const memberId = String(formData.get("memberId"));
  const active = formData.get("active") === "true";
  const supabase = await createClient();
  const { error } = await supabase.from("school_members").update({ active }).eq("id", memberId);
  if (error) throw new Error(error.message);
  revalidatePath("/equipe");
  revalidatePath(`/equipe/${memberId}`);
}

/**
 * Enregistre l'écran d'accès d'une personne : rôles, accès par module et
 * permissions sensibles. Un module réglé comme ses rôles n'a pas d'ajustement.
 */
export async function saveMemberAccess(_prev: TeamState, formData: FormData): Promise<TeamState> {
  await requireAdmin();
  const memberId = String(formData.get("memberId"));
  const supabase = await createClient();

  // 1. Rôles
  const wanted = new Set(formData.getAll("roles").map(String));
  const { data: current } = await supabase.from("member_roles").select("role_id").eq("member_id", memberId);
  const have = new Set((current ?? []).map((r) => r.role_id as string));
  const toAdd = [...wanted].filter((r) => !have.has(r));
  const toRemove = [...have].filter((r) => !wanted.has(r));
  if (toAdd.length) {
    const { error } = await supabase.from("member_roles").insert(toAdd.map((role_id) => ({ member_id: memberId, role_id })));
    if (error) return { error: dbMessage(error) };
  }
  if (toRemove.length) {
    const { error } = await supabase.from("member_roles").delete().eq("member_id", memberId).in("role_id", toRemove);
    if (error) return { error: dbMessage(error) };
  }

  // 2. Accès par module, comparés à ce que les rôles (mis à jour) donnent.
  const derived = await roleDerivedAccess(memberId);
  const upserts: { member_id: string; module: string; access: number; scope: Perm["scope"] }[] = [];
  const clears: string[] = [];
  for (const m of MODULES) {
    const access = Number(formData.get(`access_${m}`) ?? derived[m].access);
    const scope = formData.get(`scope_${m}`) === "all" ? "all" : "own_classes";
    // Module non touché à l'écran : on garde son état (et les nouveaux rôles s'appliquent).
    if (formData.get(`orig_${m}`) === `${access}:${access > 0 ? scope : "-"}`) continue;
    const same = access === derived[m].access && (access === 0 || scope === derived[m].scope);
    if (same) clears.push(m);
    else upserts.push({ member_id: memberId, module: m, access, scope });
  }
  if (clears.length) {
    const { error } = await supabase.from("member_overrides").delete().eq("member_id", memberId).in("module", clears);
    if (error) return { error: dbMessage(error) };
  }
  if (upserts.length) {
    const { error } = await supabase.from("member_overrides").upsert(upserts, { onConflict: "member_id,module" });
    if (error) return { error: dbMessage(error) };
  }

  // 3. Permissions sensibles
  const wantSens = new Set(formData.getAll("sensitive").map(String).filter((p) => (SENSITIVE as readonly string[]).includes(p)));
  const { data: curSens } = await supabase.from("member_sensitive").select("perm").eq("member_id", memberId);
  const haveSens = new Set((curSens ?? []).map((r) => r.perm as string));
  const sensAdd = [...wantSens].filter((p) => !haveSens.has(p));
  const sensRemove = [...haveSens].filter((p) => !wantSens.has(p));
  if (sensAdd.length) {
    const { error } = await supabase.from("member_sensitive").insert(sensAdd.map((perm) => ({ member_id: memberId, perm })));
    if (error) return { error: dbMessage(error) };
  }
  if (sensRemove.length) {
    const { error } = await supabase.from("member_sensitive").delete().eq("member_id", memberId).in("perm", sensRemove);
    if (error) return { error: dbMessage(error) };
  }

  revalidatePath(`/equipe/${memberId}`);
  revalidatePath("/equipe");
  return { ok: "saved" };
}

export async function resetMemberOverrides(formData: FormData) {
  await requireAdmin();
  const memberId = String(formData.get("memberId"));
  const supabase = await createClient();
  const { error } = await supabase.from("member_overrides").delete().eq("member_id", memberId);
  if (error) throw new Error(error.message);
  revalidatePath(`/equipe/${memberId}`);
}
