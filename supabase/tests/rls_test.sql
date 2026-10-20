-- Tests de sécurité EkolNet. Lancer après supabase_stub.sql + la migration :
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/rls_test.sql
-- Chaque vérification affiche « ok » ou arrête le script avec la raison.
\set QUIET on
\pset tuples_only on

create or replace function ok(p_cond boolean, p_label text) returns text
language plpgsql as $$
begin
  if p_cond is not true then
    raise exception 'ÉCHEC : %', p_label;
  end if;
  return 'ok   ' || p_label;
end $$;
-- Vrai si l'instruction est refusée (erreur de permission ou de règle).
create or replace function refused(p_sql text) returns boolean
language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when insufficient_privilege or check_violation or raise_exception or invalid_parameter_value then
  return true;
end $$;
grant execute on function ok(boolean, text), refused(text) to authenticated;

insert into auth.users (id, email, phone) values
  ('00000000-0000-0000-0000-00000000000a', 'owner@test.ht', null),
  ('00000000-0000-0000-0000-00000000000b', 'admin@test.ht', null),
  ('00000000-0000-0000-0000-00000000000c', 'prof@test.ht', null),
  ('00000000-0000-0000-0000-00000000000d', 'sec@test.ht', null),
  ('00000000-0000-0000-0000-00000000000e', 'caisse@test.ht', null),
  ('00000000-0000-0000-0000-00000000000f', null, '50937412286'),
  ('00000000-0000-0000-0000-000000000010', 'sabrina@test.ht', null),
  ('00000000-0000-0000-0000-000000000011', 'autre@test.ht', null);

-- Raccourcis : se connecter en tant que…
\set as_owner  'reset role; select set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-00000000000a'', false); set role authenticated;'
\set as_admin  'reset role; select set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-00000000000b'', false); set role authenticated;'
\set as_prof   'reset role; select set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-00000000000c'', false); set role authenticated;'
\set as_sec    'reset role; select set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-00000000000d'', false); set role authenticated;'
\set as_cash   'reset role; select set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-00000000000e'', false); set role authenticated;'
\set as_parent 'reset role; select set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-00000000000f'', false); set role authenticated;'
\set as_stu    'reset role; select set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-000000000010'', false); set role authenticated;'
\set as_other  'reset role; select set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-000000000011'', false); set role authenticated;'

\echo '— Création des écoles'
:as_owner
select create_school('École Nouvel Espoir', 'Port-au-Prince', 'Jean Louis') as school \gset
:as_other
select create_school('Collège Autre', 'Cap-Haïtien', 'Autre Directeur') as other_school \gset

:as_owner
select ok((select count(*) from roles where school_id = :'school') = 5, 'cinq rôles modèles créés');
select ok((select count(*) from periods where school_id = :'school') = 3, 'trois contrôles créés');
select ok((select count(*) from schools) = 1, 'le propriétaire ne voit que son école');
select id as year from school_years where school_id = :'school' \gset
select id as period1 from periods where school_id = :'school' and position = 1 \gset

\echo '— Équipe : propriétaire, admin, employés'
insert into school_members (school_id, user_id, full_name, level)
  values (:'school', '00000000-0000-0000-0000-00000000000b', 'Marie Lamè', 'admin');
select ok(true, 'le propriétaire nomme un admin');

:as_admin
insert into school_members (school_id, user_id, full_name, title) values
  (:'school', '00000000-0000-0000-0000-00000000000c', 'Pierre Saint-Fleur', 'Physique'),
  (:'school', '00000000-0000-0000-0000-00000000000d', 'Carline Dorval', 'Bureau'),
  (:'school', '00000000-0000-0000-0000-00000000000e', 'Wilson Bien-Aimé', 'Bureau');
select ok(true, 'l''admin ajoute des employés');
select ok(refused($$update school_members set level = 'admin' where full_name = 'Carline Dorval'$$),
  'l''admin ne peut pas nommer un autre admin');
select ok(refused($$update school_members set active = false where level = 'owner'$$),
  'personne ne désactive le propriétaire');
select ok(refused($$insert into school_members (school_id, user_id, full_name, level) values ('$$ || :'other_school' || $$', '00000000-0000-0000-0000-00000000000c', 'X', 'employee')$$),
  'l''admin ne peut rien ajouter dans une autre école');

select id as m_prof from school_members where full_name = 'Pierre Saint-Fleur' \gset
select id as m_sec from school_members where full_name = 'Carline Dorval' \gset
select id as m_cash from school_members where full_name = 'Wilson Bien-Aimé' \gset
select id as m_admin from school_members where full_name = 'Marie Lamè' \gset
insert into member_roles (member_id, role_id)
  select :'m_prof', id from roles where school_id = :'school' and name = 'Professeur';
insert into member_roles (member_id, role_id)
  select :'m_sec', id from roles where school_id = :'school' and name = 'Secrétaire';
insert into member_roles (member_id, role_id)
  select :'m_cash', id from roles where school_id = :'school' and name = 'Caissier';
select ok(refused($$insert into member_sensitive (member_id, perm) values ('$$ || :'m_admin' || $$', 'view_salaries')$$),
  'l''admin ne modifie pas les accès d''un autre admin');

\echo '— Classes, matières, élèves'
insert into classes (school_id, year_id, name, cycle) values
  (:'school', :'year', '5e AF A', 'primaire'), (:'school', :'year', 'NS2 A', 'secondaire'), (:'school', :'year', 'NS1 A', 'secondaire');
select id as c_prim from classes where name = '5e AF A' \gset
select id as c_ns2 from classes where name = 'NS2 A' \gset
select id as c_ns1 from classes where name = 'NS1 A' \gset
insert into subjects (school_id, class_id, name, max_points) values
  (:'school', :'c_ns2', 'Physique', 80), (:'school', :'c_ns2', 'Chimie', 60),
  (:'school', :'c_prim', 'Mathématiques', 100), (:'school', :'c_ns1', 'Physique', 80);
select id as s_phys from subjects where class_id = :'c_ns2' and name = 'Physique' \gset
select id as s_chim from subjects where class_id = :'c_ns2' and name = 'Chimie' \gset
select id as s_math from subjects where class_id = :'c_prim' \gset
select id as s_phys1 from subjects where class_id = :'c_ns1' \gset
insert into teaching_assignments (member_id, subject_id, school_id, class_id)
  values (:'m_prof', :'s_phys', :'school', :'c_ns2');

:as_sec
insert into students (school_id, matricule, first_name, last_name, sex) values
  (:'school', 'EK-2026-0101', 'Wood', 'Jean-Baptiste', 'M'),
  (:'school', 'EK-2026-0102', 'Sabrina', 'Jean-Baptiste', 'F'),
  (:'school', 'EK-2026-0103', 'Kervens', 'Pierre', 'M');
select ok(true, 'la secrétaire inscrit des élèves');
select id as st_wood from students where first_name = 'Wood' \gset
select id as st_sab from students where first_name = 'Sabrina' \gset
select id as st_ker from students where first_name = 'Kervens' \gset
insert into enrollments (school_id, student_id, class_id, year_id) values
  (:'school', :'st_wood', :'c_prim', :'year'), (:'school', :'st_sab', :'c_ns2', :'year'), (:'school', :'st_ker', :'c_ns1', :'year');
insert into guardians (school_id, full_name, phone) values (:'school', 'Marie Jean-Baptiste', '+509 37 41 2286');
select id as g_marie from guardians where full_name = 'Marie Jean-Baptiste' \gset
insert into student_guardians (student_id, guardian_id) values (:'st_wood', :'g_marie'), (:'st_sab', :'g_marie');
select ok(refused($$insert into payments (school_id, student_id, year_id, amount, method) values ('$$ || :'school' || $$', '$$ || :'st_wood' || $$', '$$ || :'year' || $$', 1000, 'cash')$$),
  'la secrétaire (finances : voir) ne peut pas encaisser');

reset role;
update students set user_id = '00000000-0000-0000-0000-000000000010' where id = :'st_sab';
:as_other
select ok(refused($$insert into enrollments (school_id, student_id, class_id, year_id) select school_id, '$$ || :'st_wood' || $$', id, year_id from classes limit 1$$)
  or (select count(*) from classes) = 0, 'une autre école ne peut pas inscrire nos élèves');
select ok((select count(*) from students) = 0, 'une autre école ne voit aucun de nos élèves');

\echo '— Professeur : seulement ses classes, pas les finances'
:as_prof
select ok((select count(*) from students) = 1, 'le professeur voit seulement les élèves de NS2 A');
select ok((select count(*) from payments) = 0, 'le professeur ne voit pas les paiements');
insert into grades (school_id, student_id, subject_id, period_id, value) values (:'school', :'st_sab', :'s_phys', :'period1', 62);
select ok(true, 'le professeur saisit une note en physique NS2 A');
select ok(refused($$insert into grades (school_id, student_id, subject_id, period_id, value) values ('$$ || :'school' || $$', '$$ || :'st_sab' || $$', '$$ || :'s_chim' || $$', '$$ || :'period1' || $$', 40)$$),
  'le professeur ne note pas une matière qu''il n''enseigne pas');
select ok(refused($$insert into grades (school_id, student_id, subject_id, period_id, value) values ('$$ || :'school' || $$', '$$ || :'st_ker' || $$', '$$ || :'s_phys1' || $$', '$$ || :'period1' || $$', 40)$$),
  'le professeur ne note pas une autre classe');
select ok(refused($$update grades set value = 90 where student_id = '$$ || :'st_sab' || $$'$$),
  'une note ne peut pas dépasser le maximum');
update grades set locked = true where student_id = :'st_sab';
select ok(refused($$update grades set value = 70 where student_id = '$$ || :'st_sab' || $$'$$),
  'une note soumise ne change plus pour le professeur');
insert into homework (school_id, class_id, subject_id, kind, title, instructions, due_on, out_of)
  values (:'school', :'c_ns2', :'s_phys', 'app', 'Devoir 3 : les forces', 'Exercices 4 à 7 page 52.', current_date + 6, 20);
insert into convocations (school_id, class_id, subject_id, title, reason, starts_at, room)
  values (:'school', :'c_ns2', :'s_phys', 'Cours de rattrapage', 'Devoir 1 manqué', now() + interval '3 days', 'Labo');
select id as conv from convocations \gset
insert into convocation_students (convocation_id, student_id, school_id) values (:'conv', :'st_sab', :'school');
select ok(true, 'le professeur donne un devoir et convoque une élève');
select ok(refused($$insert into homework (school_id, class_id, subject_id, kind, title, due_on) values ('$$ || :'school' || $$', '$$ || :'c_prim' || $$', '$$ || :'s_math' || $$', 'home', 'X', current_date)$$),
  'le professeur ne donne pas de devoir dans une autre classe');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
insert into homework (school_id, class_id, subject_id, kind, title, instructions, due_on)
  values (:'school', :'c_prim', :'s_math', 'home', 'Exercices 3 et 4, page 52', 'Dans le cahier de devoirs.', current_date + 2);

\echo '— Caissier : encaissement, reçus, annulation'
:as_cash
insert into payments (school_id, student_id, year_id, amount, method) values (:'school', :'st_wood', :'year', 7500, 'cash');
insert into payments (school_id, student_id, year_id, amount, method) values (:'school', :'st_sab', :'year', 5000, 'moncash');
select ok((select string_agg(receipt_no, ',' order by receipt_no) from payments) = 'R-000001,R-000002', 'numéros de reçu attribués dans l''ordre');
select ok(refused($$update payments set amount = 1 where receipt_no = 'R-000001'$$) or (select amount from payments where receipt_no = 'R-000001') = 7500, 'le caissier ne modifie pas un paiement');
select ok(refused($$delete from payments where receipt_no = 'R-000001'$$) or (select count(*) from payments) = 2, 'un paiement ne se supprime jamais');
select ok((select count(*) from grades) = 0, 'le caissier ne voit pas les notes');
:as_owner
select ok(refused($$update payments set voided = true where receipt_no = 'R-000001'$$), 'annuler un reçu exige une raison');
update payments set voided = true, void_reason = 'Erreur de saisie' where receipt_no = 'R-000002';
select ok((select voided_by from payments where receipt_no = 'R-000002') = '00000000-0000-0000-0000-00000000000a', 'l''annulation est signée');
-- Ajustement personnel : le caissier reçoit aussi l'inscription.
insert into member_overrides (member_id, module, access, scope) values (:'m_cash', 'enrollment', 2, 'all');
:as_cash
select ok(module_access(:'school', 'enrollment') = 2, 'l''ajustement personnel donne l''inscription au caissier');
select ok(module_access(:'school', 'grades') = 0, 'le caissier n''a toujours pas les notes');

\echo '— Parent : primaire et secondaire'
:as_parent
select ok(link_my_family() = 1, 'le parent connecté par SMS est relié à sa fiche');
select ok((select count(*) from students) = 2, 'le parent voit ses deux enfants seulement');
select ok((select count(*) from payments) = 2, 'le parent voit les paiements de ses enfants');
select ok((select count(*) from grades) = 1, 'le parent voit la note soumise');
select ok((select count(*) from homework) = 1, 'le parent lit le contenu du devoir du primaire seulement');
select ok((select bool_and(instructions is null) from family_homework(:'st_sab')), 'au secondaire, le parent ne voit pas la consigne');
select ok((select count(*) from family_homework(:'st_sab')) = 1, 'au secondaire, le parent voit que le devoir existe');
select ok((select count(*) from convocations) = 1, 'le parent voit la convocation');
update convocation_students set acknowledged_by = null where student_id = :'st_sab';
select ok((select acknowledged_by from convocation_students where student_id = :'st_sab') = '00000000-0000-0000-0000-00000000000f', 'le parent prend connaissance (signé automatiquement)');
select ok(refused($$update convocation_students set attended = true where student_id = '$$ || :'st_sab' || $$'$$), 'le parent ne marque pas la présence');
select ok(refused($$update guardians set phone = '0000' where id = '$$ || :'g_marie' || $$'$$), 'le parent ne change pas son numéro lui-même');
update guardians set lang = 'ht' where id = :'g_marie';
select ok((select lang from guardians where id = :'g_marie') = 'ht', 'le parent choisit le créole');
select ok((select count(*) from audit_log) = 0, 'le parent ne lit pas le journal');

\echo '— Élève du secondaire'
:as_stu
select ok((select count(*) from students) = 1, 'l''élève ne voit que sa fiche');
select ok((select count(*) from homework) = 1, 'l''élève lit son devoir');
select ok((select bool_and(content_visible) from family_homework(:'st_sab')), 'l''élève voit la consigne');
insert into homework_submissions (homework_id, student_id, school_id, status, photo_path)
  select id, :'st_sab', :'school', 'submitted', 'remises/sab.jpg' from homework where class_id = :'c_ns2';
select ok(true, 'l''élève remet son devoir');
select ok(refused($$update homework_submissions set grade = 20 where student_id = '$$ || :'st_sab' || $$'$$), 'l''élève ne se met pas de note');
select ok((select count(*) from convocations) = 1, 'l''élève voit la même convocation');

\echo '— Blocage du bulletin'
:as_sec
select ok(refused($$insert into bulletin_blocks (school_id, student_id, period_id, reason) values ('$$ || :'school' || $$', '$$ || :'st_sab' || $$', '$$ || :'period1' || $$', 'unpaid_balance')$$),
  'sans la permission, la secrétaire ne bloque pas un bulletin');
:as_owner
insert into member_sensitive (member_id, perm) values (:'m_sec', 'block_bulletin');
:as_sec
insert into bulletin_blocks (school_id, student_id, period_id, reason, note) values (:'school', :'st_sab', :'period1', 'unpaid_balance', 'Solde 7 500 HTG');
select ok(true, 'avec la permission, la secrétaire bloque le bulletin');
:as_parent
select ok((select count(*) from grades where student_id = :'st_sab') = 0, 'bulletin bloqué : le parent ne voit plus les notes de la période');
select ok(is_bulletin_blocked(:'st_sab', :'period1'), 'le parent voit que le bulletin est bloqué');
select ok((select count(*) from bulletin_blocks) = 0, 'le parent ne voit pas la raison du blocage');
:as_stu
select ok((select count(*) from grades) = 0, 'bulletin bloqué : l''élève non plus');

\echo '— Journal d''accès'
:as_admin
select ok((select count(*) from audit_log where action like 'member_roles%') = 3, 'les rôles donnés sont dans le journal');
select ok((select count(*) from audit_log where action like 'bulletin_blocks%') = 1, 'le blocage est dans le journal');
select ok(refused($$delete from audit_log$$) or (select count(*) from audit_log) > 0, 'le journal ne s''efface pas');
select ok(refused($$update audit_log set action = 'x'$$) or not exists (select 1 from audit_log where action = 'x'), 'le journal ne se modifie pas');

\echo '— Transfert de propriété'
:as_admin
select ok(refused($$select transfer_ownership('$$ || :'school' || $$', '$$ || :'m_admin' || $$')$$), 'un admin ne se donne pas l''école');
:as_owner
select transfer_ownership(:'school', :'m_admin');
select ok((select level from school_members where id = :'m_admin') = 'owner', 'le nouveau propriétaire est Marie');
select ok((select count(*) from school_members where school_id = :'school' and level = 'owner') = 1, 'toujours un seul propriétaire');

reset role;
\echo 'Tous les tests sont passés.'
