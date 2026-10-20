# EkolNet

Platfòm jesyon lekòl: enskripsyon, nòt, kanè, kès, devwa, konvokasyon ak relasyon ak paran yo.
Lang pa defo a se Fransè; Kreyòl disponib toupatou.

- **Sit wèb ak app:** Next.js (ka enstale sou telefòn tankou yon app, PWA)
- **Baz done, koneksyon, sekirite:** Supabase (gratis, pa bezwen kat bank)

## Sa ki fèt deja (Etap 1 ak 2)

- Tout baz done a: lekòl, ekip, wòl ak pèmisyon, ane, kontwòl, klas, matyè, elèv, paran,
  frè, peman ak resi, nòt, prezans, disiplin, devwa, konvokasyon, blokaj kanè, jounal aksè.
- Règ sekirite yo andedan baz done a (RLS): menm si yon moun eseye kontoune sit la,
  baz done a refize sa wòl li pa pèmèt. 62 tès verifye sa (`supabase/tests/rls_test.sql`).
- Kreye kont lekòl la (moun nan vin pwopriyetè), koneksyon, meni ki chanje dapre aksè chak moun.
- **Équipe et accès:** ajoute anplwaye, ba yo wòl, ajiste aksè yon moun, pèmisyon sansib,
  nonmen/retire admin (pwopriyetè sèlman), dezaktive yon kont.
- **Journal d'accès:** tout chanjman aksè, pèsonn pa ka efase yo.

Pwochen etap: elèv ak enskripsyon, kès ak resi, nòt ak kanè, prezans, devwa, app paran yo.

## Enstale l sou òdinatè w

Ou bezwen **Node.js 20 oubyen pi resan** (ou deja genyen l) ak yon kont **Supabase** (gratis).

### 1. Kreye pwojè Supabase la

1. Ale sou <https://supabase.com>, konekte ak GitHub ou, peze **New project**.
   Non: `ekolnet`. Rejyon: *East US* (pi pre Ayiti). Kenbe modpas baz done a yon kote.
2. Lè pwojè a pare, ale nan **SQL Editor** → **New query**.
3. Louvri fichye `supabase/migrations/20261020000000_init.sql`, kopye tout sa ki ladan l,
   kole l nan SQL Editor a, epi peze **Run**. Ou dwe wè «Success. No rows returned».
4. Ale nan **Authentication → Sign In / Providers → Email** epi dezaktive
   **Confirm email** pandan w ap teste (konsa ou pa bezwen konfime imèl ou chak fwa).
   Lè platfòm nan pare pou lekòl yo, n ap reaktive l.

### 2. Konekte sit la ak Supabase

1. Nan Supabase: **Project Settings → API**. Ou pral wè `Project URL`, kle `anon public`
   ak kle `service_role` (sekrè).
2. Nan dosye EkolNet la, kopye `.env.example` epi rele kopi a `.env.local`.
3. Ranpli 3 valè yo nan `.env.local`.
   **Pa janm** mete `.env.local` sou GitHub, e pa janm bay pèsonn kle `service_role` la.

### 3. Lanse l

Louvri dosye a nan VS Code, louvri Terminal la (`Ctrl+ù` oubyen *View → Terminal*), epi tape:

```
npm install
npm run dev
```

Louvri <http://localhost:3000> nan navigatè a. Peze **Créer le compte de votre école**,
ranpli fòm nan: se ou ki pral pwopriyetè lekòl la.

### 4. Eseye sistèm aksè a

1. Nan **Équipe et accès**, ajoute yon anplwaye (egz. yon pwofesè) ak wòl *Professeur*.
2. Dekonekte w, konekte ak imèl ak modpas pwovizwa anplwaye a.
3. Ou ap wè meni an chanje: pwofesè a pa wè *Caisse* ni *Équipe et accès*.
4. Retounen kòm pwopriyetè, chanje yon aksè pou moun sa a, epi gade **Journal d'accès**.

## Tès sekirite yo (opsyonèl)

Si ou gen PostgreSQL sou òdinatè w:

```
createdb ekolnet_test
psql -d ekolnet_test -f supabase/tests/supabase_stub.sql
psql -d ekolnet_test -f supabase/migrations/20261020000000_init.sql
psql -d ekolnet_test -f supabase/tests/rls_test.sql
```

Dènye liy lan dwe di «Tous les tests sont passés.»

## Òganizasyon kòd la

```
app/
  connexion/          paj koneksyon
  creer-ecole/        kreye kont lekòl la (pwopriyetè)
  (ecole)/            tout paj ki gen meni an
    tableau-de-bord/
    equipe/           ekip, wòl, aksè pa moun
    journal/          jounal aksè
lib/
  access.ts           kiyes ki konekte, ki lekòl, ki aksè
  i18n.ts             tèks Fransè ak Kreyòl
  supabase/server.ts  koneksyon ak Supabase
supabase/
  migrations/         baz done a ak règ sekirite yo
  tests/              tès sekirite yo
```
