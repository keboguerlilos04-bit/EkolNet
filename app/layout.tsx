import type { Metadata, Viewport } from "next";
import { getLang } from "@/lib/i18n";
import "./globals.css";

export const metadata: Metadata = {
  title: "EkolNet",
  description: "Gestion d'école : inscriptions, notes, bulletins, caisse et parents.",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#15284d",
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const lang = await getLang();
  return (
    <html lang={lang === "ht" ? "ht" : "fr"}>
      <body>{children}</body>
    </html>
  );
}
