"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

export type NavGroup = { label: string; items: { href: string; label: string }[] };

export function NavLinks({ groups }: { groups: NavGroup[] }) {
  const path = usePathname();
  return (
    <nav className="nav">
      {groups.map((g) => (
        <div key={g.label} style={{ display: "contents" }}>
          <div className="navgrp">{g.label}</div>
          {g.items.map((it) => (
            <Link key={it.href} href={it.href} aria-current={path === it.href || path.startsWith(it.href + "/") ? "page" : undefined}>
              {it.label}
            </Link>
          ))}
        </div>
      ))}
    </nav>
  );
}
