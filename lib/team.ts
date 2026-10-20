import { MODULES } from "@/lib/access";
import { createClient } from "@/lib/supabase/server";

export type Perm = { access: number; scope: "own_classes" | "all" };

/** Ce que les rôles donnent à cette personne, module par module (sans ajustement). */
export async function roleDerivedAccess(memberId: string): Promise<Record<string, Perm>> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("member_roles")
    .select("role:roles(role_permissions(module, access, scope))")
    .eq("member_id", memberId);
  const out: Record<string, Perm> = {};
  for (const m of MODULES) out[m] = { access: 0, scope: "own_classes" };
  for (const row of (data ?? []) as unknown as { role: { role_permissions: { module: string; access: number; scope: Perm["scope"] }[] } | null }[]) {
    for (const p of row.role?.role_permissions ?? []) {
      const cur = out[p.module];
      if (!cur) continue;
      cur.access = Math.max(cur.access, p.access);
      if (p.access > 0 && p.scope === "all") cur.scope = "all";
    }
  }
  return out;
}

