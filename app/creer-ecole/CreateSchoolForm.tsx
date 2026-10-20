"use client";

import { useActionState } from "react";
import { createSchool, type CreateSchoolState } from "./actions";
import { SubmitButton } from "@/components/SubmitButton";
import type { Messages } from "@/lib/i18n";

export function CreateSchoolForm({ t, needsAccount }: { t: Messages; needsAccount: boolean }) {
  const [state, action] = useActionState<CreateSchoolState, FormData>(createSchool, null);
  const f = state?.fields ?? {};
  const msg = (key?: string) => (key ? (t[key as keyof Messages] ?? t.genericError) : null);

  if (state?.notice) {
    return <p className="info" role="status">{msg(state.notice)}</p>;
  }

  return (
    <form action={action} noValidate>
      {state?.error && <p className="error" role="alert">{msg(state.error)}</p>}
      <div className="field">
        <label htmlFor="fullName">{t.yourName}</label>
        <input id="fullName" name="fullName" type="text" autoComplete="name" required defaultValue={f.fullName} />
      </div>
      <div className="field">
        <label htmlFor="phone">{t.phone}</label>
        <input id="phone" name="phone" type="tel" autoComplete="tel" placeholder="+509 37 00 0000" defaultValue={f.phone} />
      </div>
      <div className="field">
        <label htmlFor="schoolName">{t.schoolName}</label>
        <input id="schoolName" name="schoolName" type="text" required placeholder="École Nouvel Espoir" defaultValue={f.schoolName} />
      </div>
      <div className="field">
        <label htmlFor="city">{t.city}</label>
        <input id="city" name="city" type="text" placeholder="Port-au-Prince" defaultValue={f.city} />
      </div>
      {needsAccount && (
        <>
          <div className="field">
            <label htmlFor="email">{t.email}</label>
            <input id="email" name="email" type="email" autoComplete="email" required defaultValue={f.email} />
          </div>
          <div className="field">
            <label htmlFor="password">{t.password}</label>
            <input id="password" name="password" type="password" autoComplete="new-password" minLength={8} required />
            <span className="faint">{t.passwordHint}</span>
          </div>
        </>
      )}
      <SubmitButton>{t.createSchool}</SubmitButton>
    </form>
  );
}
