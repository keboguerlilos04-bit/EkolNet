"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type CreateSchoolState = { error?: string; notice?: string; fields?: Record<string, string> } | null;

/**
 * Crée le compte de connexion (si besoin) puis l'école. La personne devient
 * propriétaire. La fonction create_school de la base crée aussi les rôles
 * modèles, l'année en cours et les trois contrôles.
 */
export async function createSchool(_prev: CreateSchoolState, formData: FormData): Promise<CreateSchoolState> {
  const fields = {
    fullName: String(formData.get("fullName") ?? "").trim(),
    phone: String(formData.get("phone") ?? "").trim(),
    schoolName: String(formData.get("schoolName") ?? "").trim(),
    city: String(formData.get("city") ?? "").trim(),
    email: String(formData.get("email") ?? "").trim(),
  };
  const password = String(formData.get("password") ?? "");

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!fields.fullName || !fields.schoolName || (!user && (!fields.email || !password))) {
    return { error: "required", fields };
  }

  if (!user) {
    if (password.length < 8) return { error: "passwordTooShort", fields };
    const { data, error } = await supabase.auth.signUp({
      email: fields.email,
      password,
      options: { data: { full_name: fields.fullName } },
    });
    if (error) {
      return { error: /already|registered|exists/i.test(error.message) ? "emailTaken" : "genericError", fields };
    }
    if (!data.session) {
      // La confirmation par e-mail est activée dans Supabase : la personne
      // confirmera, se connectera, puis terminera la création de l'école.
      return { notice: "confirmEmail", fields };
    }
  }

  const { error } = await supabase.rpc("create_school", {
    p_name: fields.schoolName,
    p_city: fields.city || null,
    p_full_name: fields.fullName,
    p_phone: fields.phone || null,
  });
  if (error) return { error: "genericError", fields };

  redirect("/tableau-de-bord");
}
