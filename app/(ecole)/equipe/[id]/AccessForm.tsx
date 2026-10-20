"use client";

import { useActionState, useState } from "react";
import { saveMemberAccess, type TeamState } from "../actions";
import { SubmitButton } from "@/components/SubmitButton";
import type { Messages } from "@/lib/i18n";

type Perm = { access: number; scope: "own_classes" | "all" };

export function AccessForm(props: {
  t: Messages;
  memberId: string;
  modules: { key: string; label: string }[];
  sensitive: { key: string; label: string }[];
  roles: { id: string; name: string; description: string | null }[];
  memberRoleIds: string[];
  effective: Record<string, Perm>;
  derived: Record<string, Perm>;
  sensitiveOn: string[];
  locked: boolean;
}) {
  const { t } = props;
  const [state, action] = useActionState<TeamState, FormData>(saveMemberAccess, null);
  const [values, setValues] = useState<Record<string, Perm>>(props.effective);
  const changed = (m: string) => {
    const v = values[m];
    const d = props.derived[m];
    return v.access !== d.access || (v.access > 0 && v.scope !== d.scope);
  };
  const msg = (key?: string) => (key ? (t[key as keyof Messages] ?? key) : null);
  const levels = [t.none, t.view, t.edit];

  return (
    <form action={action}>
      <input type="hidden" name="memberId" value={props.memberId} />
      {state?.error && <p className="error" role="alert">{msg(state.error)}</p>}
      {state?.ok && <p className="info" role="status">{msg(state.ok)}</p>}

      <fieldset className="card" disabled={props.locked} style={{ margin: "0 0 16px" }}>
        <h2>{t.rolesOf}</h2>
        <div className="checks">
          {props.roles.map((r) => (
            <label key={r.id} title={r.description ?? undefined}>
              <input type="checkbox" name="roles" value={r.id} defaultChecked={props.memberRoleIds.includes(r.id)} /> {r.name}
            </label>
          ))}
        </div>
      </fieldset>

      <fieldset className="card" disabled={props.locked} style={{ margin: "0 0 16px" }}>
        <h2>{t.accessOf}</h2>
        <p className="faint" style={{ margin: "-6px 0 10px" }}>
          <span className="dot" />{t.fromRoles} &nbsp; <span className="dot changed" />{t.personal}
        </p>
        <div className="tbl">
          <table>
            <thead>
              <tr><th>{t.module}</th><th>{t.level}</th><th>{t.scope}</th></tr>
            </thead>
            <tbody>
              {props.modules.map((m) => {
                const v = values[m.key];
                return (
                  <tr key={m.key}>
                    <td>
                      <input type="hidden" name={`orig_${m.key}`} value={`${props.effective[m.key].access}:${props.effective[m.key].access > 0 ? props.effective[m.key].scope : "-"}`} />
                      <span className={`dot${changed(m.key) ? " changed" : ""}`} />{m.label}
                    </td>
                    <td>
                      <div className="seg" role="radiogroup" aria-label={m.label}>
                        {levels.map((label, i) => (
                          <label key={i}>
                            <input
                              type="radio"
                              name={`access_${m.key}`}
                              value={i}
                              checked={v.access === i}
                              onChange={() => setValues({ ...values, [m.key]: { ...v, access: i } })}
                            />
                            {label}
                          </label>
                        ))}
                      </div>
                    </td>
                    <td>
                      {v.access > 0 ? (
                        <select
                          name={`scope_${m.key}`}
                          value={v.scope}
                          aria-label={`${t.scope} · ${m.label}`}
                          onChange={(e) => setValues({ ...values, [m.key]: { ...v, scope: e.target.value as Perm["scope"] } })}
                          style={{ width: "auto" }}
                        >
                          <option value="own_classes">{t.ownClasses}</option>
                          <option value="all">{t.allSchool}</option>
                        </select>
                      ) : (
                        <span className="faint">—</span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </fieldset>

      <fieldset className="card" disabled={props.locked} style={{ margin: "0 0 16px" }}>
        <h2>{t.sensitiveTitle}</h2>
        <p className="faint" style={{ margin: "-6px 0 10px" }}>{t.sensitiveIntro}</p>
        <div className="checks" style={{ flexDirection: "column" }}>
          {props.sensitive.map((s) => (
            <label key={s.key}>
              <input type="checkbox" name="sensitive" value={s.key} defaultChecked={props.sensitiveOn.includes(s.key)} /> {s.label}
            </label>
          ))}
        </div>
      </fieldset>

      {!props.locked && (
        <div className="row">
          <span className="sp" />
          <SubmitButton>{t.save}</SubmitButton>
        </div>
      )}
    </form>
  );
}
