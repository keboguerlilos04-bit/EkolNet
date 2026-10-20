"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { LANG_COOKIE } from "@/lib/i18n";
import { createClient } from "@/lib/supabase/server";

export async function setLang(formData: FormData) {
  const lang = formData.get("lang") === "ht" ? "ht" : "fr";
  (await cookies()).set(LANG_COOKIE, lang, { path: "/", maxAge: 60 * 60 * 24 * 365, sameSite: "lax" });
  revalidatePath("/", "layout");
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/connexion");
}
