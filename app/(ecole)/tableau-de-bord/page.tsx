import { getSchoolContext } from "@/lib/access";
import { getMessages } from "@/lib/i18n";
import { createClient } from "@/lib/supabase/server";

export default async function DashboardPage() {
  const ctx = (await getSchoolContext())!;
  const { t } = await getMessages();
  const supabase = await createClient();
  const schoolId = ctx.school!.id;

  // Chaque compte respecte les règles : un professeur ne compte que ses élèves.
  const [students, team, classes, year] = await Promise.all([
    supabase.from("students").select("id", { count: "exact", head: true }).eq("school_id", schoolId),
    supabase.from("school_members").select("id", { count: "exact", head: true }).eq("school_id", schoolId).eq("active", true),
    supabase.from("classes").select("id", { count: "exact", head: true }).eq("school_id", schoolId),
    supabase.from("school_years").select("name").eq("school_id", schoolId).eq("is_current", true).maybeSingle(),
  ]);

  return (
    <>
      <h1 style={{ fontSize: 22, margin: 0 }}>{t.hello}, {ctx.member!.fullName}</h1>
      <div className="grid">
        <div className="card stat"><div className="lab">{t.statStudents}</div><div className="val num">{students.count ?? 0}</div></div>
        <div className="card stat"><div className="lab">{t.statClasses}</div><div className="val num">{classes.count ?? 0}</div></div>
        <div className="card stat"><div className="lab">{t.statTeam}</div><div className="val num">{team.count ?? 0}</div></div>
        <div className="card stat"><div className="lab">{t.currentYear}</div><div className="val">{year.data?.name ?? "—"}</div></div>
      </div>
      <div className="card">
        <div className="row">
          <div>
            <div className="muted" style={{ fontSize: 13 }}>{t.schoolCode}</div>
            <div className="num" style={{ fontSize: 20, fontWeight: 700, letterSpacing: ".08em" }}>{ctx.school!.code}</div>
          </div>
        </div>
      </div>
    </>
  );
}
