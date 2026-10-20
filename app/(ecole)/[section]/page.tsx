import { notFound } from "next/navigation";
import { getMessages } from "@/lib/i18n";

// Modules de l'étape suivante : la page existe pour que le menu fonctionne.
const SECTIONS: Record<string, "students" | "enrollment" | "grades" | "attendance" | "homework" | "bulletins" | "finance"> = {
  eleves: "students",
  inscription: "enrollment",
  notes: "grades",
  presences: "attendance",
  devoirs: "homework",
  bulletins: "bulletins",
  caisse: "finance",
};

export default async function UpcomingSection({ params }: { params: Promise<{ section: string }> }) {
  const { section } = await params;
  const key = SECTIONS[section];
  if (!key) notFound();
  const { t } = await getMessages();
  return (
    <div className="card">
      <h2>{t[key]}</h2>
      <p className="muted" style={{ margin: 0 }}>{t.comingSoon}</p>
    </div>
  );
}
