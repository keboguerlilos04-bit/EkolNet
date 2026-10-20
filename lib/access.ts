import { cache } from "react";
import { createClient } from "@/lib/supabase/server";

export type Level = "owner" | "admin" | "employee";
export type ModuleAccess = { access: 0 | 1 | 2; scopeAll: boolean };

export type SchoolContext = {
  userId: string;
  email: string | null;
  member: { id: string; fullName: string; level: Level; title: string | null } | null;
  school: { id: string; name: string; code: string; city: string | null } | null;
  access: Record<string, ModuleAccess>;
};

export const MODULES = [
  "dashboard", "students", "enrollment", "grades", "attendance", "discipline",
  "homework", "convocations", "finance", "communication", "reports",
  "calendar", "staff_payroll", "bulletin_blocks",
] as const;

export const SENSITIVE = [
  "view_salaries", "void_receipt", "edit_locked_grades", "export_data",
  "read_private_messages", "block_bulletin",
] as const;

/**
 * Qui est connecté, dans quelle école, et ce qu'il peut voir.
 * Les accès viennent de la base (fonction my_access) : l'interface
 * cache ce qui n'est pas permis, et la base refuse de toute façon.
 */
export const getSchoolContext = cache(async (): Promise<SchoolContext | null> => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: memberships } = await supabase
    .from("school_members")
    .select("id, full_name, level, title, school:schools(id, name, code, city)")
    .eq("user_id", user.id)
    .eq("active", true)
    .order("created_at", { ascending: true })
    .limit(1);

  const row = memberships?.[0] as
    | { id: string; full_name: string; level: Level; title: string | null; school: SchoolContext["school"] }
    | undefined;

  if (!row || !row.school) {
    return { userId: user.id, email: user.email ?? null, member: null, school: null, access: {} };
  }

  const { data: accessRows } = await supabase.rpc("my_access", { p_school: row.school.id });
  const access: Record<string, ModuleAccess> = {};
  for (const a of (accessRows ?? []) as { module: string; access: number; scope_all: boolean }[]) {
    access[a.module] = { access: Math.max(0, Math.min(2, a.access)) as 0 | 1 | 2, scopeAll: a.scope_all };
  }

  return {
    userId: user.id,
    email: user.email ?? null,
    member: { id: row.id, fullName: row.full_name, level: row.level, title: row.title },
    school: row.school,
    access,
  };
});

export function canSee(ctx: SchoolContext, module: string): boolean {
  return (ctx.access[module]?.access ?? 0) >= 1;
}

export function isAdminLevel(ctx: SchoolContext): boolean {
  return ctx.member?.level === "owner" || ctx.member?.level === "admin";
}
