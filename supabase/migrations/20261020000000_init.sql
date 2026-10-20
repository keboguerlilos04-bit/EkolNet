-- EkolNet — schéma initial
-- Multi-école : chaque ligne porte school_id ; la sécurité (RLS) garantit
-- qu'une personne ne voit que les données de son école, selon son rôle.
--
-- Niveaux de pouvoir (school_members.level) :
--   owner    : propriétaire, un seul par école, voit tout, seul à nommer/retirer des admins
--   admin    : gère les employés et leurs accès, ne touche ni au propriétaire ni aux autres admins
--   employee : ne voit que ce que ses rôles + ajustements lui donnent
-- Accès par module : 0 = pas d'accès, 1 = voir, 2 = modifier ; portée own_classes | all.


-- ───────────────────────── Types ─────────────────────────
create type member_level as enum ('owner', 'admin', 'employee');
create type access_scope as enum ('own_classes', 'all');
create type school_cycle as enum ('primaire', 'secondaire');
create type student_status as enum ('active', 'transferred', 'withdrawn', 'draft');
create type pay_method as enum ('cash', 'moncash', 'natcash', 'bank');
create type attendance_status as enum ('present', 'absent', 'late');
create type homework_kind as enum ('app', 'home');
create type submission_status as enum ('todo', 'submitted', 'late', 'missing', 'graded');
create type discipline_kind as enum ('note', 'sanction', 'exclusion');

-- Modules soumis aux permissions (liste fermée).
create domain app_module as text check (value in (
  'dashboard', 'students', 'enrollment', 'grades', 'attendance', 'discipline',
  'homework', 'convocations', 'finance', 'communication', 'reports',
  'calendar', 'staff_payroll', 'bulletin_blocks'
));

-- Permissions sensibles : jamais données automatiquement à un employé.
create domain sensitive_perm as text check (value in (
  'view_salaries', 'void_receipt', 'edit_locked_grades', 'export_data',
  'read_private_messages', 'block_bulletin'
));

-- ───────────────────────── École et équipe ─────────────────────────
create table schools (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 120),
  code text not null unique check (code ~ '^[A-Z0-9]{4,10}$'),
  city text,
  default_lang text not null default 'fr' check (default_lang in ('fr', 'ht')),
  owner_id uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table school_members (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  full_name text not null,
  phone text,
  title text,                         -- ex. « Physique · NS2 A », purement informatif
  level member_level not null default 'employee',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (school_id, user_id)
);
-- Un seul propriétaire par école.
create unique index one_owner_per_school on school_members (school_id) where level = 'owner';

create table roles (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  name text not null,
  description text,
  created_at timestamptz not null default now(),
  unique (school_id, name)
);

create table role_permissions (
  role_id uuid not null references roles(id) on delete cascade,
  module app_module not null,
  access smallint not null check (access between 0 and 2),
  scope access_scope not null default 'all',
  primary key (role_id, module)
);

create table member_roles (
  member_id uuid not null references school_members(id) on delete cascade,
  role_id uuid not null references roles(id) on delete cascade,
  primary key (member_id, role_id)
);

-- Ajustement pour une seule personne : remplace ce que ses rôles donnent pour ce module.
create table member_overrides (
  member_id uuid not null references school_members(id) on delete cascade,
  module app_module not null,
  access smallint not null check (access between 0 and 2),
  scope access_scope not null default 'all',
  primary key (member_id, module)
);

create table member_sensitive (
  member_id uuid not null references school_members(id) on delete cascade,
  perm sensitive_perm not null,
  primary key (member_id, perm)
);

-- Journal d'accès : ni modifiable ni supprimable (aucune policy update/delete).
create table audit_log (
  id bigint generated always as identity primary key,
  school_id uuid not null references schools(id) on delete cascade,
  actor_id uuid,
  action text not null,
  target_member_id uuid,
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);

-- ───────────────────────── Structure académique ─────────────────────────
create table school_years (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  name text not null,                 -- « 2026–2027 »
  starts_on date not null,
  ends_on date not null check (ends_on > starts_on),
  is_current boolean not null default false,
  unique (school_id, name)
);
create unique index one_current_year on school_years (school_id) where is_current;

create table periods (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  year_id uuid not null references school_years(id) on delete cascade,
  name text not null,                 -- « 1er contrôle », « 1er trimestre »
  position smallint not null,
  unique (year_id, position)
);

create table classes (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  year_id uuid not null references school_years(id) on delete cascade,
  name text not null,                 -- « 5e AF A », « NS2 A »
  cycle school_cycle not null,        -- primaire : pas de compte élève, le parent gère tout
  homeroom_member_id uuid references school_members(id) on delete set null, -- titulaire
  unique (year_id, name)
);

create table subjects (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  class_id uuid not null references classes(id) on delete cascade,
  name text not null,
  max_points numeric(6,2) not null default 100 check (max_points > 0),
  coefficient numeric(5,2) not null default 1 check (coefficient > 0),
  unique (class_id, name)
);

create table teaching_assignments (
  member_id uuid not null references school_members(id) on delete cascade,
  subject_id uuid not null references subjects(id) on delete cascade,
  school_id uuid not null references schools(id) on delete cascade,
  class_id uuid not null references classes(id) on delete cascade,
  primary key (member_id, subject_id)
);

-- ───────────────────────── Élèves et familles ─────────────────────────
create table students (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  matricule text not null,
  first_name text not null,
  last_name text not null,
  sex char(1) check (sex in ('F', 'M')),
  birth_date date,
  photo_path text,
  user_id uuid references auth.users(id),   -- compte élève (secondaire seulement)
  status student_status not null default 'active',
  created_at timestamptz not null default now(),
  unique (school_id, matricule)
);

create table enrollments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  class_id uuid not null references classes(id) on delete cascade,
  year_id uuid not null references school_years(id) on delete cascade,
  unique (student_id, year_id)
);

create table guardians (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  full_name text not null,
  phone text not null,                -- relie le parent à l'école toute l'année
  user_id uuid references auth.users(id),
  lang text not null default 'fr' check (lang in ('fr', 'ht')),
  unique (school_id, phone)
);

create table student_guardians (
  student_id uuid not null references students(id) on delete cascade,
  guardian_id uuid not null references guardians(id) on delete cascade,
  relation text,
  primary key (student_id, guardian_id)
);

-- ───────────────────────── Finances (POS) ─────────────────────────
create table fee_items (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  year_id uuid not null references school_years(id) on delete cascade,
  class_id uuid references classes(id) on delete cascade,   -- null = toutes les classes
  label text not null,                -- « Frais d'inscription », « Versement 1 »
  amount numeric(12,2) not null check (amount >= 0),
  due_on date
);

create table receipt_counters (
  school_id uuid primary key references schools(id) on delete cascade,
  last_no integer not null default 0
);

create table payments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  student_id uuid not null references students(id),
  year_id uuid not null references school_years(id),
  receipt_no text,                    -- attribué automatiquement : R-000913
  amount numeric(12,2) not null check (amount > 0),
  method pay_method not null,
  reference text,                     -- n° de transaction MonCash/NatCash/banque
  received_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  voided boolean not null default false,
  voided_by uuid,
  voided_at timestamptz,
  void_reason text,
  unique (school_id, receipt_no)
);

-- ───────────────────────── Vie scolaire ─────────────────────────
create table grades (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  subject_id uuid not null references subjects(id) on delete cascade,
  period_id uuid not null references periods(id) on delete cascade,
  value numeric(6,2) check (value >= 0),
  locked boolean not null default false,   -- « Soumettre à la direction »
  entered_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  unique (student_id, subject_id, period_id)
);

create table attendance (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  class_id uuid not null references classes(id) on delete cascade,
  day date not null,
  status attendance_status not null,
  guardian_note text,                 -- explication donnée par le parent
  recorded_by uuid default auth.uid(),
  unique (student_id, day)
);

create table discipline_records (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  kind discipline_kind not null,
  description text not null,
  happened_on date not null default current_date,
  created_by uuid default auth.uid()
);

create table homework (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  class_id uuid not null references classes(id) on delete cascade,
  subject_id uuid not null references subjects(id) on delete cascade,
  kind homework_kind not null,        -- app : à remettre dans l'app ; home : travail à la maison
  title text not null,
  instructions text not null default '',
  attachment_path text,
  due_on date not null,
  out_of numeric(6,2) check (out_of > 0),   -- null = pas noté
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create table homework_submissions (
  homework_id uuid not null references homework(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  school_id uuid not null references schools(id) on delete cascade,
  status submission_status not null default 'todo',
  photo_path text,
  submitted_at timestamptz,
  grade numeric(6,2),
  comment text,
  primary key (homework_id, student_id)
);

create table convocations (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  class_id uuid not null references classes(id) on delete cascade,
  subject_id uuid references subjects(id) on delete set null,
  title text not null,                -- « Cours de rattrapage »
  reason text not null,
  starts_at timestamptz not null,
  room text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create table convocation_students (
  convocation_id uuid not null references convocations(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  school_id uuid not null references schools(id) on delete cascade,
  acknowledged_by uuid,               -- le parent a pris connaissance
  acknowledged_at timestamptz,
  attended boolean,
  primary key (convocation_id, student_id)
);

-- Bulletin bloqué : pour un solde ou toute autre raison décidée par l'école.
create table bulletin_blocks (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  period_id uuid references periods(id) on delete cascade,   -- null = tous les bulletins
  reason text not null check (reason in ('unpaid_balance', 'missing_documents', 'other')),
  note text,                          -- visible par l'école seulement
  blocked_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create unique index one_block_per_period on bulletin_blocks (student_id, coalesce(period_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- Index utiles
create index on school_members (user_id);
create index on enrollments (class_id);
create index on student_guardians (guardian_id);
create index on guardians (user_id);
create index on students (user_id);
create index on payments (student_id);
create index on grades (subject_id, period_id);
create index on attendance (class_id, day);
create index on homework (class_id, due_on);
create index on audit_log (school_id, created_at desc);

-- ───────────────────────── Fonctions d'accès ─────────────────────────
-- Toutes en SECURITY DEFINER pour lire school_members sans boucle RLS.

create function my_member(p_school uuid) returns school_members
language sql stable security definer set search_path = public as $$
  select * from school_members
  where school_id = p_school and user_id = auth.uid() and active
$$;

create function is_member(p_school uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from school_members
    where school_id = p_school and user_id = auth.uid() and active)
$$;

create function is_owner(p_school uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from school_members
    where school_id = p_school and user_id = auth.uid() and active and level = 'owner')
$$;

create function is_admin(p_school uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from school_members
    where school_id = p_school and user_id = auth.uid() and active and level in ('owner', 'admin'))
$$;

-- Accès effectif à un module : propriétaire/admin = 2 ; sinon l'ajustement
-- personnel s'il existe, sinon le maximum donné par ses rôles.
create function module_access(p_school uuid, p_module text) returns smallint
language sql stable security definer set search_path = public as $$
  with m as (
    select id, level from school_members
    where school_id = p_school and user_id = auth.uid() and active
  )
  select case
    when not exists (select 1 from m) then 0::smallint
    when (select level from m) in ('owner', 'admin') then 2::smallint
    else coalesce(
      (select o.access from member_overrides o, m where o.member_id = m.id and o.module = p_module),
      (select max(rp.access) from member_roles mr join role_permissions rp on rp.role_id = mr.role_id, m
        where mr.member_id = m.id and rp.module = p_module),
      0)::smallint
  end
$$;

create function module_scope_all(p_school uuid, p_module text) returns boolean
language sql stable security definer set search_path = public as $$
  with m as (
    select id, level from school_members
    where school_id = p_school and user_id = auth.uid() and active
  )
  select case
    when not exists (select 1 from m) then false
    when (select level from m) in ('owner', 'admin') then true
    when exists (select 1 from member_overrides o, m where o.member_id = m.id and o.module = p_module)
      then (select o.scope = 'all' from member_overrides o, m where o.member_id = m.id and o.module = p_module)
    else exists (select 1 from member_roles mr join role_permissions rp on rp.role_id = mr.role_id, m
      where mr.member_id = m.id and rp.module = p_module and rp.access > 0 and rp.scope = 'all')
  end
$$;

create function has_sensitive(p_school uuid, p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select is_admin(p_school) or exists (
    select 1 from member_sensitive s join school_members m on m.id = s.member_id
    where m.school_id = p_school and m.user_id = auth.uid() and m.active and s.perm = p_perm)
$$;

-- L'employé enseigne dans cette classe, ou en est le titulaire.
create function teaches_class(p_class uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from teaching_assignments ta join school_members m on m.id = ta.member_id
    where ta.class_id = p_class and m.user_id = auth.uid() and m.active
  ) or exists (
    select 1 from classes c join school_members m on m.id = c.homeroom_member_id
    where c.id = p_class and m.user_id = auth.uid() and m.active
  )
$$;

create function teaches_subject(p_subject uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from teaching_assignments ta join school_members m on m.id = ta.member_id
    where ta.subject_id = p_subject and m.user_id = auth.uid() and m.active)
$$;

-- Accès à un module pour une classe donnée (tient compte de la portée).
create function can_class(p_school uuid, p_module text, p_class uuid, p_min int) returns boolean
language sql stable security definer set search_path = public as $$
  select module_access(p_school, p_module) >= p_min
    and (module_scope_all(p_school, p_module) or teaches_class(p_class))
$$;

create function current_class_of(p_student uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select e.class_id from enrollments e join school_years y on y.id = e.year_id
  where e.student_id = p_student order by y.is_current desc, y.starts_on desc limit 1
$$;

create function can_student(p_school uuid, p_module text, p_student uuid, p_min int) returns boolean
language sql stable security definer set search_path = public as $$
  select module_access(p_school, p_module) >= p_min
    and (module_scope_all(p_school, p_module) or teaches_class(current_class_of(p_student)))
$$;

create function is_guardian_of(p_student uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from student_guardians sg join guardians g on g.id = sg.guardian_id
    where sg.student_id = p_student and g.user_id = auth.uid())
$$;

create function is_student_self(p_student uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from students where id = p_student and user_id = auth.uid())
$$;

-- Famille = parent, ou l'élève lui-même.
create function is_family_of(p_student uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_guardian_of(p_student) or is_student_self(p_student)
$$;

create function in_school_family(p_school uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from guardians where school_id = p_school and user_id = auth.uid())
      or exists (select 1 from students where school_id = p_school and user_id = auth.uid())
$$;

create function bulletin_blocked(p_student uuid, p_period uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from bulletin_blocks b
    where b.student_id = p_student and (b.period_id is null or b.period_id = p_period))
$$;

-- ───────────────────────── Journal automatique ─────────────────────────
create function log_access_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_school uuid;
  v_target uuid;
  v_row jsonb;
begin
  v_row := to_jsonb(coalesce(new, old));
  v_target := coalesce((v_row->>'member_id')::uuid, (v_row->>'id')::uuid);
  select school_id into v_school from school_members where id = v_target;
  if v_school is null then
    v_school := (v_row->>'school_id')::uuid;
  end if;
  if v_school is null then
    return coalesce(new, old);
  end if;
  insert into audit_log (school_id, actor_id, action, target_member_id, details)
  values (v_school, auth.uid(), tg_table_name || '.' || lower(tg_op), v_target,
          jsonb_build_object('old', case when tg_op <> 'INSERT' then to_jsonb(old) end,
                             'new', case when tg_op <> 'DELETE' then to_jsonb(new) end));
  return coalesce(new, old);
end $$;

create trigger audit_member_roles after insert or delete on member_roles
  for each row execute function log_access_change();
create trigger audit_member_overrides after insert or update or delete on member_overrides
  for each row execute function log_access_change();
create trigger audit_member_sensitive after insert or delete on member_sensitive
  for each row execute function log_access_change();
create trigger audit_school_members after insert or update of level, active on school_members
  for each row execute function log_access_change();

create function log_bulletin_block() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into audit_log (school_id, actor_id, action, details)
  values (coalesce(new.school_id, old.school_id), auth.uid(), 'bulletin_blocks.' || lower(tg_op),
          jsonb_build_object('student_id', coalesce(new.student_id, old.student_id),
                             'period_id', coalesce(new.period_id, old.period_id),
                             'reason', coalesce(new.reason, old.reason)));
  return coalesce(new, old);
end $$;
create trigger audit_bulletin_blocks after insert or delete on bulletin_blocks
  for each row execute function log_bulletin_block();

-- ───────────────────────── Règles sur l'équipe ─────────────────────────
-- Un admin gère les employés ; seul le propriétaire nomme ou retire un admin ;
-- personne ne peut modifier le propriétaire (transfert via transfer_ownership).
create function guard_member_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if current_setting('ekolnet.bypass_guard', true) = 'on' then
    return coalesce(new, old);
  end if;
  if tg_op in ('UPDATE', 'DELETE') and old.level = 'owner' then
    raise exception 'Le compte du propriétaire ne peut pas être modifié ici.' using errcode = '42501';
  end if;
  if tg_op in ('INSERT', 'UPDATE') and new.level = 'owner' then
    raise exception 'Utilisez le transfert de propriété.' using errcode = '42501';
  end if;
  if not is_owner(coalesce(new.school_id, old.school_id)) then
    if (tg_op in ('UPDATE', 'DELETE') and old.level = 'admin')
       or (tg_op in ('INSERT', 'UPDATE') and new.level = 'admin') then
      raise exception 'Seul le propriétaire peut nommer ou retirer un admin.' using errcode = '42501';
    end if;
  end if;
  if tg_op = 'UPDATE' and (new.school_id <> old.school_id or new.user_id <> old.user_id) then
    raise exception 'Changement non autorisé.' using errcode = '42501';
  end if;
  return coalesce(new, old);
end $$;
create trigger guard_members before insert or update or delete on school_members
  for each row execute function guard_member_change();

-- Un admin ne peut pas changer les rôles, ajustements ou permissions d'un autre admin.
create function guard_member_access_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_member school_members;
begin
  select * into v_member from school_members where id = coalesce(new.member_id, old.member_id);
  if v_member.level in ('owner', 'admin') and not is_owner(v_member.school_id) then
    raise exception 'Seul le propriétaire peut modifier l''accès d''un admin.' using errcode = '42501';
  end if;
  return coalesce(new, old);
end $$;
create trigger guard_member_roles before insert or delete on member_roles
  for each row execute function guard_member_access_change();
create trigger guard_member_overrides before insert or update or delete on member_overrides
  for each row execute function guard_member_access_change();
create trigger guard_member_sensitive before insert or delete on member_sensitive
  for each row execute function guard_member_access_change();

-- ───────────────────────── Autres déclencheurs ─────────────────────────
-- Numéro de reçu séquentiel par école.
create function assign_receipt_no() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_no integer;
begin
  insert into receipt_counters (school_id, last_no) values (new.school_id, 1)
  on conflict (school_id) do update set last_no = receipt_counters.last_no + 1
  returning last_no into v_no;
  new.receipt_no := 'R-' || lpad(v_no::text, 6, '0');
  new.received_by := coalesce(auth.uid(), new.received_by);
  new.voided := false;
  return new;
end $$;
create trigger payments_receipt before insert on payments
  for each row execute function assign_receipt_no();

-- Un paiement ne change jamais, il peut seulement être annulé (avec raison).
create function guard_payment_update() returns trigger
language plpgsql as $$
begin
  if new.amount <> old.amount or new.student_id <> old.student_id or new.method <> old.method
     or new.receipt_no <> old.receipt_no or new.created_at <> old.created_at
     or new.received_by <> old.received_by or old.voided then
    raise exception 'Un paiement enregistré ne peut pas être modifié. Annulez-le avec une raison.' using errcode = '42501';
  end if;
  if new.voided then
    if coalesce(trim(new.void_reason), '') = '' then
      raise exception 'Indiquez la raison de l''annulation.' using errcode = '23514';
    end if;
    new.voided_by := auth.uid();
    new.voided_at := now();
  end if;
  return new;
end $$;
create trigger payments_guard before update on payments
  for each row execute function guard_payment_update();

-- Une note verrouillée ne change qu'avec la permission sensible ; une note
-- ne peut pas dépasser le maximum de la matière.
create function guard_grade() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_max numeric;
begin
  select max_points into v_max from subjects where id = new.subject_id;
  if new.value is not null and new.value > v_max then
    raise exception 'La note dépasse le maximum (%).', v_max using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and old.locked and not has_sensitive(new.school_id, 'edit_locked_grades') then
    raise exception 'Notes soumises : seule la direction peut les modifier.' using errcode = '42501';
  end if;
  new.updated_at := now();
  new.entered_by := coalesce(auth.uid(), new.entered_by);
  return new;
end $$;
create trigger grades_guard before insert or update on grades
  for each row execute function guard_grade();

-- Côté famille, une remise ne peut changer que photo/statut, jamais la note.
create function guard_submission() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_hw homework;
begin
  select * into v_hw from homework where id = new.homework_id;
  if not can_class(v_hw.school_id, 'homework', v_hw.class_id, 2) then
    if new.grade is distinct from old.grade or new.comment is distinct from old.comment
       or new.student_id <> old.student_id or new.homework_id <> old.homework_id then
      raise exception 'Seul le professeur peut noter un devoir.' using errcode = '42501';
    end if;
    if new.status not in ('submitted') then
      raise exception 'Statut non autorisé.' using errcode = '42501';
    end if;
    new.submitted_at := now();
  end if;
  return new;
end $$;
create trigger submissions_guard before update on homework_submissions
  for each row execute function guard_submission();

-- Côté famille, une convocation ne change que la prise de connaissance.
create function guard_convocation_ack() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_c convocations;
begin
  select * into v_c from convocations where id = new.convocation_id;
  if not can_class(v_c.school_id, 'convocations', v_c.class_id, 2) then
    if new.attended is distinct from old.attended
       or new.student_id <> old.student_id or new.convocation_id <> old.convocation_id then
      raise exception 'Seule l''école marque la présence.' using errcode = '42501';
    end if;
    new.acknowledged_by := auth.uid();
    new.acknowledged_at := now();
  end if;
  return new;
end $$;
create trigger convocation_ack_guard before update on convocation_students
  for each row execute function guard_convocation_ack();


-- ───────────────────────── Cohérence entre écoles ─────────────────────────
-- Chaque référence (élève, classe, matière…) doit appartenir à la même école
-- que la ligne : impossible de rattacher un élève d'une autre école.
create function check_school_refs() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_arg text;
  v_col text;
  v_tab text;
  v_ref uuid;
  v_school uuid;
begin
  foreach v_arg in array tg_argv loop
    v_col := split_part(v_arg, '=', 1);
    v_tab := split_part(v_arg, '=', 2);
    v_ref := (to_jsonb(new)->>v_col)::uuid;
    continue when v_ref is null;
    execute format('select school_id from %I where id = $1', v_tab) into v_school using v_ref;
    if v_school is distinct from new.school_id then
      raise exception 'Référence % hors de cette école.', v_col using errcode = '23514';
    end if;
  end loop;
  return new;
end $$;

create trigger same_school before insert or update on periods for each row execute function check_school_refs('year_id=school_years');
create trigger same_school before insert or update on classes for each row execute function check_school_refs('year_id=school_years', 'homeroom_member_id=school_members');
create trigger same_school before insert or update on subjects for each row execute function check_school_refs('class_id=classes');
create trigger same_school before insert or update on teaching_assignments for each row execute function check_school_refs('member_id=school_members', 'subject_id=subjects', 'class_id=classes');
create trigger same_school before insert or update on enrollments for each row execute function check_school_refs('student_id=students', 'class_id=classes', 'year_id=school_years');
create trigger same_school before insert or update on fee_items for each row execute function check_school_refs('year_id=school_years', 'class_id=classes');
create trigger same_school before insert or update on payments for each row execute function check_school_refs('student_id=students', 'year_id=school_years');
create trigger same_school before insert or update on grades for each row execute function check_school_refs('student_id=students', 'subject_id=subjects', 'period_id=periods');
create trigger same_school before insert or update on attendance for each row execute function check_school_refs('student_id=students', 'class_id=classes');
create trigger same_school before insert or update on discipline_records for each row execute function check_school_refs('student_id=students');
create trigger same_school before insert or update on homework for each row execute function check_school_refs('class_id=classes', 'subject_id=subjects');
create trigger same_school before insert or update on homework_submissions for each row execute function check_school_refs('homework_id=homework', 'student_id=students');
create trigger same_school before insert or update on convocations for each row execute function check_school_refs('class_id=classes', 'subject_id=subjects');
create trigger same_school before insert or update on convocation_students for each row execute function check_school_refs('convocation_id=convocations', 'student_id=students');
create trigger same_school before insert or update on bulletin_blocks for each row execute function check_school_refs('student_id=students', 'period_id=periods');

create function check_guardian_link() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select school_id from students where id = new.student_id)
     is distinct from (select school_id from guardians where id = new.guardian_id) then
    raise exception 'Parent et élève doivent être dans la même école.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger same_school before insert or update on student_guardians
  for each row execute function check_guardian_link();

-- Côté famille : le parent ne peut qu'expliquer une absence ou changer sa langue.
create function guard_family_attendance() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not can_class(old.school_id, 'attendance', old.class_id, 2) then
    if (to_jsonb(new) - 'guardian_note') is distinct from (to_jsonb(old) - 'guardian_note') then
      raise exception 'Le parent peut seulement donner une explication.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger attendance_family_guard before update on attendance
  for each row execute function guard_family_attendance();

create function guard_guardian_self() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.user_id = auth.uid()
     and not (module_access(old.school_id, 'enrollment') >= 2 or module_access(old.school_id, 'students') >= 2) then
    if (to_jsonb(new) - 'lang') is distinct from (to_jsonb(old) - 'lang') then
      raise exception 'Seule l''école peut modifier ces informations.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger guardians_self_guard before update on guardians
  for each row execute function guard_guardian_self();

-- Un parent qui se connecte par SMS est relié à ses fiches « parent » par son numéro.
create function link_my_family() returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_phone text;
  v_n integer;
begin
  select regexp_replace(coalesce(phone, ''), '\D', '', 'g') into v_phone from auth.users where id = auth.uid();
  if coalesce(v_phone, '') = '' then
    return 0;
  end if;
  update guardians set user_id = auth.uid()
  where user_id is null and regexp_replace(phone, '\D', '', 'g') = v_phone;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ───────────────────────── Actions (RPC) ─────────────────────────
-- Rôles modèles créés avec chaque nouvelle école (modifiables ensuite).
create function seed_role_templates(p_school uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_role uuid;
  t jsonb := '{
    "Professeur": {"desc": "Enseigne une ou plusieurs matières",
      "perms": {"dashboard":[1,"own_classes"],"students":[1,"own_classes"],"grades":[2,"own_classes"],"attendance":[2,"own_classes"],"discipline":[2,"own_classes"],"homework":[2,"own_classes"],"convocations":[2,"own_classes"],"communication":[2,"own_classes"],"calendar":[1,"all"]}},
    "Titulaire": {"desc": "Responsable d''une classe",
      "perms": {"dashboard":[1,"own_classes"],"students":[1,"own_classes"],"grades":[2,"own_classes"],"attendance":[2,"own_classes"],"discipline":[2,"own_classes"],"homework":[2,"own_classes"],"convocations":[2,"own_classes"],"communication":[2,"own_classes"],"reports":[1,"own_classes"],"calendar":[1,"all"]}},
    "Secrétaire": {"desc": "Inscriptions et dossiers",
      "perms": {"dashboard":[1,"all"],"students":[2,"all"],"enrollment":[2,"all"],"grades":[1,"all"],"attendance":[1,"all"],"discipline":[1,"all"],"convocations":[1,"all"],"finance":[1,"all"],"communication":[2,"all"],"calendar":[2,"all"],"bulletin_blocks":[1,"all"]}},
    "Caissier": {"desc": "Reçoit les paiements au bureau",
      "perms": {"dashboard":[1,"all"],"students":[1,"all"],"finance":[2,"all"],"communication":[2,"all"],"reports":[1,"all"],"bulletin_blocks":[1,"all"]}},
    "Censeur": {"desc": "Discipline et suivi académique",
      "perms": {"dashboard":[1,"all"],"students":[1,"all"],"grades":[2,"all"],"attendance":[2,"all"],"discipline":[2,"all"],"homework":[1,"all"],"convocations":[2,"all"],"communication":[2,"all"],"reports":[1,"all"],"calendar":[1,"all"]}}
  }';
begin
  for r in select key, value from jsonb_each(t) loop
    insert into roles (school_id, name, description) values (p_school, r.key, r.value->>'desc')
    returning id into v_role;
    insert into role_permissions (role_id, module, access, scope)
    select v_role, p.key, (p.value->>0)::smallint, (p.value->>1)::access_scope
    from jsonb_each(r.value->'perms') p;
  end loop;
end $$;

-- Le premier compte crée l'école et en devient propriétaire.
create function create_school(p_name text, p_city text, p_full_name text, p_phone text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_school uuid;
  v_code text;
  v_year uuid;
  v_start int := extract(year from current_date)::int - case when extract(month from current_date) < 9 then 1 else 0 end;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.' using errcode = '42501';
  end if;
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from schools where code = v_code);
  end loop;
  insert into schools (name, code, city, owner_id) values (trim(p_name), v_code, p_city, auth.uid())
  returning id into v_school;
  perform set_config('ekolnet.bypass_guard', 'on', true);
  insert into school_members (school_id, user_id, full_name, phone, level, title)
  values (v_school, auth.uid(), trim(p_full_name), p_phone, 'owner', 'Propriétaire');
  perform set_config('ekolnet.bypass_guard', 'off', true);
  perform seed_role_templates(v_school);
  insert into school_years (school_id, name, starts_on, ends_on, is_current)
  values (v_school, v_start || '–' || (v_start + 1), make_date(v_start, 9, 1), make_date(v_start + 1, 7, 15), true)
  returning id into v_year;
  insert into periods (school_id, year_id, name, position) values
    (v_school, v_year, '1er contrôle', 1), (v_school, v_year, '2e contrôle', 2), (v_school, v_year, '3e contrôle', 3);
  return v_school;
end $$;

-- Le propriétaire transmet l'école à un admin existant ; il devient admin.
create function transfer_ownership(p_school uuid, p_new_owner_member uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_target school_members;
begin
  if not is_owner(p_school) then
    raise exception 'Seul le propriétaire peut transférer l''école.' using errcode = '42501';
  end if;
  select * into v_target from school_members where id = p_new_owner_member and school_id = p_school and active;
  if v_target.id is null or v_target.level <> 'admin' then
    raise exception 'Le nouveau propriétaire doit d''abord être admin.' using errcode = '22023';
  end if;
  perform set_config('ekolnet.bypass_guard', 'on', true);
  update school_members set level = 'admin' where school_id = p_school and level = 'owner';
  update school_members set level = 'owner' where id = p_new_owner_member;
  update schools set owner_id = v_target.user_id where id = p_school;
  perform set_config('ekolnet.bypass_guard', 'off', true);
  insert into audit_log (school_id, actor_id, action, target_member_id)
  values (p_school, auth.uid(), 'ownership.transfer', p_new_owner_member);
end $$;

-- Ce que voit la personne connectée : ses écoles, son niveau, ses accès.
create function my_access(p_school uuid)
returns table (module text, access smallint, scope_all boolean)
language sql stable security definer set search_path = public as $$
  select m.module, module_access(p_school, m.module), module_scope_all(p_school, m.module)
  from unnest(array['dashboard','students','enrollment','grades','attendance','discipline',
    'homework','convocations','finance','communication','reports','calendar',
    'staff_payroll','bulletin_blocks']) as m(module)
$$;

-- Devoirs vus par un parent : le contenu seulement pour le primaire ;
-- au secondaire, le parent voit titre, date, statut et résultat.
create function family_homework(p_student uuid)
returns table (id uuid, subject text, kind homework_kind, title text, instructions text,
               due_on date, out_of numeric, status submission_status, grade numeric, comment text,
               content_visible boolean)
language sql stable security definer set search_path = public as $$
  select h.id, s.name, h.kind, h.title,
    case when c.cycle = 'primaire' or is_student_self(p_student) then h.instructions end,
    h.due_on, h.out_of,
    coalesce(hs.status, 'todo'), hs.grade, hs.comment,
    (c.cycle = 'primaire' or is_student_self(p_student))
  from homework h
  join classes c on c.id = h.class_id
  join subjects s on s.id = h.subject_id
  left join homework_submissions hs on hs.homework_id = h.id and hs.student_id = p_student
  where is_family_of(p_student)
    and h.class_id = current_class_of(p_student)
  order by h.due_on desc
$$;

-- ───────────────────────── Sécurité (RLS) ─────────────────────────
alter table schools enable row level security;
alter table school_members enable row level security;
alter table roles enable row level security;
alter table role_permissions enable row level security;
alter table member_roles enable row level security;
alter table member_overrides enable row level security;
alter table member_sensitive enable row level security;
alter table audit_log enable row level security;
alter table school_years enable row level security;
alter table periods enable row level security;
alter table classes enable row level security;
alter table subjects enable row level security;
alter table teaching_assignments enable row level security;
alter table students enable row level security;
alter table enrollments enable row level security;
alter table guardians enable row level security;
alter table student_guardians enable row level security;
alter table fee_items enable row level security;
alter table receipt_counters enable row level security;
alter table payments enable row level security;
alter table grades enable row level security;
alter table attendance enable row level security;
alter table discipline_records enable row level security;
alter table homework enable row level security;
alter table homework_submissions enable row level security;
alter table convocations enable row level security;
alter table convocation_students enable row level security;
alter table bulletin_blocks enable row level security;

-- École
create policy schools_read on schools for select
  using (is_member(id) or in_school_family(id));
create policy schools_update on schools for update
  using (is_owner(id)) with check (is_owner(id));

-- Équipe et accès : visibles par toute l'équipe (noms), gérés par les admins.
create policy members_read on school_members for select using (is_member(school_id));
create policy members_insert on school_members for insert with check (is_admin(school_id));
create policy members_update on school_members for update using (is_admin(school_id)) with check (is_admin(school_id));

create policy roles_read on roles for select using (is_member(school_id));
create policy roles_write on roles for all using (is_admin(school_id)) with check (is_admin(school_id));

create policy role_perms_read on role_permissions for select
  using (exists (select 1 from roles r where r.id = role_id and is_member(r.school_id)));
create policy role_perms_write on role_permissions for all
  using (exists (select 1 from roles r where r.id = role_id and is_admin(r.school_id)))
  with check (exists (select 1 from roles r where r.id = role_id and is_admin(r.school_id)));

create policy member_roles_read on member_roles for select
  using (exists (select 1 from school_members m where m.id = member_id and is_member(m.school_id)));
create policy member_roles_write on member_roles for all
  using (exists (select 1 from school_members m where m.id = member_id and is_admin(m.school_id)))
  with check (exists (select 1 from school_members m join roles r on r.school_id = m.school_id
    where m.id = member_id and r.id = role_id and is_admin(m.school_id)));

create policy overrides_read on member_overrides for select
  using (exists (select 1 from school_members m where m.id = member_id
    and (is_admin(m.school_id) or m.user_id = auth.uid())));
create policy overrides_write on member_overrides for all
  using (exists (select 1 from school_members m where m.id = member_id and is_admin(m.school_id)))
  with check (exists (select 1 from school_members m where m.id = member_id and is_admin(m.school_id)));

create policy sensitive_read on member_sensitive for select
  using (exists (select 1 from school_members m where m.id = member_id
    and (is_admin(m.school_id) or m.user_id = auth.uid())));
create policy sensitive_write on member_sensitive for all
  using (exists (select 1 from school_members m where m.id = member_id and is_admin(m.school_id)))
  with check (exists (select 1 from school_members m where m.id = member_id and is_admin(m.school_id)));

-- Journal : lecture admin, écriture seulement par les déclencheurs.
create policy audit_read on audit_log for select using (is_admin(school_id));

-- Structure académique : lisible par l'école et les familles.
create policy years_read on school_years for select using (is_member(school_id) or in_school_family(school_id));
create policy years_write on school_years for all using (is_admin(school_id)) with check (is_admin(school_id));
create policy periods_read on periods for select using (is_member(school_id) or in_school_family(school_id));
create policy periods_write on periods for all using (is_admin(school_id)) with check (is_admin(school_id));
create policy classes_read on classes for select using (is_member(school_id) or in_school_family(school_id));
create policy classes_write on classes for all using (is_admin(school_id)) with check (is_admin(school_id));
create policy subjects_read on subjects for select using (is_member(school_id) or in_school_family(school_id));
create policy subjects_write on subjects for all using (is_admin(school_id)) with check (is_admin(school_id));
create policy teaching_read on teaching_assignments for select using (is_member(school_id));
create policy teaching_write on teaching_assignments for all using (is_admin(school_id)) with check (is_admin(school_id));

-- Élèves
create policy students_read on students for select
  using (can_student(school_id, 'students', id, 1) or is_family_of(id));
create policy students_insert on students for insert
  with check (module_access(school_id, 'enrollment') >= 2);
create policy students_update on students for update
  using (module_access(school_id, 'students') >= 2 and module_scope_all(school_id, 'students'))
  with check (module_access(school_id, 'students') >= 2 and module_scope_all(school_id, 'students'));

create policy enrollments_read on enrollments for select
  using (can_class(school_id, 'students', class_id, 1) or is_family_of(student_id));
create policy enrollments_write on enrollments for all
  using (module_access(school_id, 'enrollment') >= 2)
  with check (module_access(school_id, 'enrollment') >= 2);

create policy guardians_read on guardians for select
  using (user_id = auth.uid() or exists (select 1 from student_guardians sg
    where sg.guardian_id = id and can_student(school_id, 'students', sg.student_id, 1)));
create policy guardians_write on guardians for all
  using (module_access(school_id, 'enrollment') >= 2 or module_access(school_id, 'students') >= 2)
  with check (module_access(school_id, 'enrollment') >= 2 or module_access(school_id, 'students') >= 2);
create policy guardians_self_lang on guardians for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy sg_read on student_guardians for select
  using (is_family_of(student_id) or exists (select 1 from students s
    where s.id = student_id and can_student(s.school_id, 'students', s.id, 1)));
create policy sg_write on student_guardians for all
  using (exists (select 1 from students s where s.id = student_id
    and (module_access(s.school_id, 'enrollment') >= 2 or module_access(s.school_id, 'students') >= 2)))
  with check (exists (select 1 from students s where s.id = student_id
    and (module_access(s.school_id, 'enrollment') >= 2 or module_access(s.school_id, 'students') >= 2)));

-- Finances : jamais de suppression ; annulation seulement avec la permission sensible.
create policy fees_read on fee_items for select
  using (module_access(school_id, 'finance') >= 1 or in_school_family(school_id));
create policy fees_write on fee_items for all
  using (is_admin(school_id)) with check (is_admin(school_id));

create policy payments_read on payments for select
  using (module_access(school_id, 'finance') >= 1 or is_family_of(student_id));
create policy payments_insert on payments for insert
  with check (module_access(school_id, 'finance') >= 2);
create policy payments_void on payments for update
  using (has_sensitive(school_id, 'void_receipt'))
  with check (has_sensitive(school_id, 'void_receipt'));

-- Notes : la famille ne voit rien d'une période dont le bulletin est bloqué.
create policy grades_read on grades for select
  using (
    exists (select 1 from subjects s where s.id = subject_id and can_class(school_id, 'grades', s.class_id, 1))
    or (is_family_of(student_id) and locked and not bulletin_blocked(student_id, period_id))
  );
create policy grades_write on grades for insert
  with check (exists (select 1 from subjects s where s.id = subject_id
    and module_access(school_id, 'grades') >= 2
    and (module_scope_all(school_id, 'grades') or teaches_subject(s.id))));
create policy grades_update on grades for update
  using (exists (select 1 from subjects s where s.id = subject_id
    and module_access(school_id, 'grades') >= 2
    and (module_scope_all(school_id, 'grades') or teaches_subject(s.id))))
  with check (exists (select 1 from subjects s where s.id = subject_id
    and module_access(school_id, 'grades') >= 2
    and (module_scope_all(school_id, 'grades') or teaches_subject(s.id))));

-- Présences
create policy attendance_read on attendance for select
  using (can_class(school_id, 'attendance', class_id, 1) or is_family_of(student_id));
create policy attendance_write on attendance for insert
  with check (can_class(school_id, 'attendance', class_id, 2));
create policy attendance_update on attendance for update
  using (can_class(school_id, 'attendance', class_id, 2))
  with check (can_class(school_id, 'attendance', class_id, 2));
create policy attendance_explain on attendance for update
  using (is_guardian_of(student_id) and status <> 'present')
  with check (is_guardian_of(student_id));

-- Discipline (sanctions, exclusions) : vue par la famille.
create policy discipline_read on discipline_records for select
  using (can_student(school_id, 'discipline', student_id, 1) or is_family_of(student_id));
create policy discipline_write on discipline_records for insert
  with check (can_student(school_id, 'discipline', student_id, 2));
create policy discipline_update on discipline_records for update
  using (can_student(school_id, 'discipline', student_id, 2))
  with check (can_student(school_id, 'discipline', student_id, 2));

-- Devoirs : contenu lisible par l'élève du secondaire et par le parent au primaire ;
-- le parent du secondaire passe par family_homework() (sans le contenu).
create policy homework_read on homework for select
  using (
    can_class(school_id, 'homework', class_id, 1)
    or exists (select 1 from students st join classes c on c.id = homework.class_id
      where st.user_id = auth.uid() and current_class_of(st.id) = homework.class_id)
    or exists (select 1 from student_guardians sg join guardians g on g.id = sg.guardian_id
      join classes c on c.id = homework.class_id
      where g.user_id = auth.uid() and c.cycle = 'primaire' and current_class_of(sg.student_id) = homework.class_id)
  );
create policy homework_write on homework for insert
  with check (module_access(school_id, 'homework') >= 2
    and (module_scope_all(school_id, 'homework') or teaches_subject(subject_id)));
create policy homework_update on homework for update
  using (can_class(school_id, 'homework', class_id, 2) and (created_by = auth.uid() or is_admin(school_id)))
  with check (can_class(school_id, 'homework', class_id, 2));
create policy homework_delete on homework for delete
  using (can_class(school_id, 'homework', class_id, 2) and (created_by = auth.uid() or is_admin(school_id)));

create policy submissions_read on homework_submissions for select
  using (is_family_of(student_id) or exists (select 1 from homework h
    where h.id = homework_id and can_class(h.school_id, 'homework', h.class_id, 1)));
create policy submissions_teacher on homework_submissions for all
  using (exists (select 1 from homework h where h.id = homework_id and can_class(h.school_id, 'homework', h.class_id, 2)))
  with check (exists (select 1 from homework h where h.id = homework_id and can_class(h.school_id, 'homework', h.class_id, 2)));
create policy submissions_student_insert on homework_submissions for insert
  with check (is_student_self(student_id) and status = 'submitted');
create policy submissions_student_update on homework_submissions for update
  using (is_student_self(student_id)) with check (is_student_self(student_id));

-- Convocations : même information pour l'élève et le parent.
create function conv_can(p_conv uuid, p_min int) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from convocations c where c.id = p_conv and can_class(c.school_id, 'convocations', c.class_id, p_min))
$$;
create function conv_family(p_conv uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from convocation_students cs where cs.convocation_id = p_conv and is_family_of(cs.student_id))
$$;

create policy convocations_read on convocations for select
  using (can_class(school_id, 'convocations', class_id, 1) or conv_family(id));
create policy convocations_write on convocations for insert
  with check (can_class(school_id, 'convocations', class_id, 2));
create policy convocations_update on convocations for update
  using (can_class(school_id, 'convocations', class_id, 2))
  with check (can_class(school_id, 'convocations', class_id, 2));

create policy conv_students_read on convocation_students for select
  using (is_family_of(student_id) or conv_can(convocation_id, 1));
create policy conv_students_write on convocation_students for insert
  with check (conv_can(convocation_id, 2));
create policy conv_students_update on convocation_students for update
  using (is_guardian_of(student_id) or conv_can(convocation_id, 2))
  with check (is_guardian_of(student_id) or conv_can(convocation_id, 2));

-- Blocage du bulletin : l'école voit la raison ; la famille passe par is_bulletin_blocked().
create policy blocks_read on bulletin_blocks for select
  using (module_access(school_id, 'bulletin_blocks') >= 1 or has_sensitive(school_id, 'block_bulletin'));
create policy blocks_insert on bulletin_blocks for insert
  with check (has_sensitive(school_id, 'block_bulletin'));
create policy blocks_delete on bulletin_blocks for delete
  using (has_sensitive(school_id, 'block_bulletin'));

-- La famille sait seulement si le bulletin est disponible, sans la raison.
create function is_bulletin_blocked(p_student uuid, p_period uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case when is_family_of(p_student) or is_member((select school_id from students where id = p_student))
    then bulletin_blocked(p_student, p_period) end
$$;

-- ───────────────────────── Droits PostgREST ─────────────────────────
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
revoke insert, update, delete on audit_log from authenticated;
revoke all on receipt_counters from authenticated;
grant execute on all functions in schema public to authenticated;
revoke execute on function seed_role_templates(uuid) from public, authenticated;
revoke execute on function log_access_change() from public, authenticated;
revoke execute on function log_bulletin_block() from public, authenticated;
revoke execute on function check_school_refs() from public, authenticated;
