"use client";

import { useActionState, useEffect, useRef } from "react";
import { addEmployee, type TeamState } from "./actions";
import { SubmitButton } from "@/components/SubmitButton";
import type { Messages } from "@/lib/i18n";

export function AddEmployeeForm({ t, roles }: { t: Messages; roles: { id: string; name: string }[] }) {
  const [state, action] = useActionState<TeamState, FormData>(addEmployee, null);
  const formRef = useRef<HTMLFormElement>(null);
  useEffect(() => {
    if (state?.ok) formRef.current?.reset();
  }, [state]);
  const msg = (key?: string) => (key ? (t[key as keyof Messages] ?? key) : null);
  const f = state?.fields ?? {};

  return (
    <form ref={formRef} action={action} className="card" noValidate>
      <h2>{t.addEmployee}</h2>
      {state?.error && <p className="error" role="alert">{msg(state.error)}</p>}
      {state?.ok && <p className="info" role="status">{msg(state.ok)}</p>}
      <div className="form">
        <div className="field">
          <label htmlFor="e_name">{t.fullName}</label>
          <input id="e_name" name="fullName" type="text" required defaultValue={f.fullName} />
        </div>
        <div className="field">
          <label htmlFor="e_title">{t.title}</label>
          <input id="e_title" name="title" type="text" placeholder={t.titlePlaceholder} defaultValue={f.title} />
        </div>
        <div className="field">
          <label htmlFor="e_email">{t.email}</label>
          <input id="e_email" name="email" type="email" required defaultValue={f.email} />
        </div>
        <div className="field">
          <label htmlFor="e_phone">{t.phone}</label>
          <input id="e_phone" name="phone" type="tel" placeholder="+509 37 00 0000" defaultValue={f.phone} />
        </div>
        <div className="field">
          <label htmlFor="e_pass">{t.tempPassword}</label>
          <input id="e_pass" name="password" type="text" minLength={8} required autoComplete="off" />
          <span className="faint">{t.tempPasswordHint}</span>
        </div>
      </div>
      <div className="field" style={{ marginTop: 14 }}>
        <label>{t.initialRoles}</label>
        <div className="checks">
          {roles.map((r) => (
            <label key={r.id}>
              <input type="checkbox" name="roles" value={r.id} /> {r.name}
            </label>
          ))}
        </div>
      </div>
      <div className="row" style={{ marginTop: 16 }}>
        <span className="sp" />
        <SubmitButton>{t.add}</SubmitButton>
      </div>
    </form>
  );
}
