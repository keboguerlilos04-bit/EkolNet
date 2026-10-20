"use client";

import { useActionState } from "react";
import { signIn, type FormState } from "./actions";
import { SubmitButton } from "@/components/SubmitButton";
import type { Messages } from "@/lib/i18n";

export function LoginForm({ t }: { t: Messages }) {
  const [state, action] = useActionState<FormState, FormData>(signIn, null);
  return (
    <form action={action} noValidate>
      {state?.error && (
        <p className="error" role="alert">
          {t[state.error as keyof Messages] ?? t.genericError}
        </p>
      )}
      <div className="field">
        <label htmlFor="email">{t.email}</label>
        <input id="email" name="email" type="email" autoComplete="email" required defaultValue={state?.fields?.email} />
      </div>
      <div className="field">
        <label htmlFor="password">{t.password}</label>
        <input id="password" name="password" type="password" autoComplete="current-password" required />
      </div>
      <SubmitButton>{t.signIn}</SubmitButton>
    </form>
  );
}
