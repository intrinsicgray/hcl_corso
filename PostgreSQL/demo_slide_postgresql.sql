-- =============================================================================
-- Demo di esempio, slide per slide · Giorno 1 (PostgreSQL)
--
-- Ogni script ha sopra un commento con il codice e il nome della slide.
-- Prerequisito: dump_corso.sql già eseguito (schema legacy + schema public).
-- Esegui un blocco alla volta (selezione + "Esegui istruzione SQL").
--
-- Convenzioni
--   "-- atteso:"       risultato misurato sul dataset del corso (PostgreSQL 16)
--   "-- DA SOLA:"      istruzione che dà errore apposta: eseguila da sola
--   "-- [A] / [B]"     passi di una demo a due sessioni: due editor con PID diversi
--   Gli script che modificano dati sono in BEGIN … ROLLBACK, o lavorano nello schema demo.
--   Le demo sugli indici creano indici temporanei dentro una transazione annullata,
--   quindi non dipendono dallo stato del laboratorio.
-- =============================================================================

SET search_path TO public;
SET max_parallel_workers_per_gather = 0;



-- =============================================================================
-- Setup · mini-dataset per le slide 1.03 – 1.14 (schema demo)
-- =============================================================================

DROP SCHEMA IF EXISTS demo CASCADE;
CREATE SCHEMA demo;

CREATE TABLE demo.customers (
  id   int PRIMARY KEY,
  name text NOT NULL,
  city text                               -- nullable di proposito
);

CREATE TABLE demo.orders (
  id          int PRIMARY KEY,
  customer_id int REFERENCES demo.customers (id),   -- nullable di proposito (ordine ospite)
  total       numeric(8,2) NOT NULL,
  coupon      text                                  -- nullable di proposito
);

INSERT INTO demo.customers VALUES (1, 'Rossi', 'Roma'), (2, 'Bianchi', 'Milano'), (3, 'Verdi', NULL);
INSERT INTO demo.orders    VALUES (10, 1, 100.00, 'SPRING'), (11, 1, 50.00, NULL), (12, 2, 75.00, NULL);



-- =============================================================================
-- Slide 1.03 · Modello relazionale, chiavi e integrità
-- =============================================================================

SELECT * FROM demo.customers;
SELECT * FROM demo.customers ORDER BY name DESC;           -- nessun ordine garantito senza ORDER BY

SELECT ctid, * FROM demo.customers;                        -- posizione fisica: (0,1) (0,2) (0,3)

-- DA SOLA: foreign key, cliente inesistente
INSERT INTO demo.orders VALUES (99, 42, 10.00, NULL);
-- errore: violates foreign key constraint "orders_customer_id_fkey"

-- DA SOLA: foreign key, cliente ancora referenziato
DELETE FROM demo.customers WHERE id = 1;
-- errore: violates foreign key constraint on table "orders"



-- =============================================================================
-- Slide 1.04 · Normalizzazione: il problema
-- =============================================================================

-- Lo stesso cliente compare con due nomi nella tabella piatta del legacy
SELECT cliente_email, array_agg(DISTINCT cliente_nome ORDER BY cliente_nome) AS nomi
FROM legacy.ordini_flat
WHERE cliente_email = 'cliente72@shop.it'
GROUP BY cliente_email;
-- atteso: {"N. Cognome 72","Nome Cognome 72"}

SELECT ordine_id, cliente_email, cliente_nome, cliente_paese, riga, sku, prodotto, prezzo, qta
FROM legacy.ordini_flat
WHERE ordine_id IN (53, 106)
ORDER BY ordine_id, riga;



-- =============================================================================
-- Slide 1.05a · Forme normali: le dipendenze funzionali
-- =============================================================================

-- "A determina B" se a ogni valore di A corrisponde un solo valore di B.
-- Zero righe = la dipendenza regge.

-- ordine_id → data, cliente, stato
SELECT ordine_id
FROM legacy.ordini_flat
GROUP BY ordine_id
HAVING count(DISTINCT data_ordine) > 1 OR count(DISTINCT cliente_email) > 1 OR count(DISTINCT stato) > 1;
-- atteso: nessuna riga

-- sku → nome del prodotto
SELECT sku FROM legacy.ordini_flat GROUP BY sku HAVING count(DISTINCT prodotto) > 1;
-- atteso: nessuna riga

-- cliente_email → nome: NON regge nei dati sporchi del legacy
SELECT count(*) AS clienti_con_piu_nomi
FROM (SELECT cliente_email FROM legacy.ordini_flat
      WHERE cliente_email IS NOT NULL
      GROUP BY cliente_email HAVING count(DISTINCT cliente_nome) > 1) x;
-- atteso: 37

-- (ordine_id, riga) è la chiave, ma nell'export ci sono righe duplicate
SELECT count(*) AS coppie_duplicate
FROM (SELECT ordine_id, riga FROM legacy.ordini_flat GROUP BY 1, 2 HAVING count(*) > 1) x;
-- atteso: 10



-- =============================================================================
-- Slide 1.05b · Seconda forma normale, con un esempio
-- =============================================================================

-- Data e stato dipendono da ordine_id soltanto: vanno in una tabella orders
SELECT DISTINCT ordine_id, data_ordine, stato
FROM legacy.ordini_flat
WHERE ordine_id IN (53, 106)
ORDER BY ordine_id;

-- Resta la riga d'ordine
SELECT ordine_id, riga, sku, qta
FROM legacy.ordini_flat
WHERE ordine_id IN (53, 106)
ORDER BY ordine_id, riga;



-- =============================================================================
-- Slide 1.05c · Terza forma normale, con un esempio
-- =============================================================================

-- Il cliente dipende dall'ordine solo tramite l'email: nome e paese vanno in customers
SELECT DISTINCT ordine_id, cliente_email, cliente_nome, cliente_paese
FROM legacy.ordini_flat
WHERE ordine_id IN (53, 353, 106, 406)
ORDER BY cliente_email, ordine_id;

-- Un solo posto per cliente: si tiene il nome più completo
SELECT DISTINCT ON (cliente_email) cliente_email, cliente_nome, upper(cliente_paese) AS paese
FROM legacy.ordini_flat
WHERE cliente_email IN ('cliente72@shop.it', 'cliente143@shop.it')
ORDER BY cliente_email, length(cliente_nome) DESC;
-- atteso: "Nome Cognome 72" · "Nome Cognome 143"



-- =============================================================================
-- Slide 1.05d · Forme normali: lo schema risultante
-- =============================================================================

SELECT (SELECT count(DISTINCT cliente_email) FROM legacy.ordini_flat) AS clienti,
       (SELECT count(DISTINCT sku)            FROM legacy.ordini_flat) AS prodotti,
       (SELECT count(DISTINCT ordine_id)      FROM legacy.ordini_flat) AS ordini,
       (SELECT count(*) FROM (SELECT DISTINCT ordine_id, riga FROM legacy.ordini_flat) d) AS righe;
-- atteso: 300 · 40 · 2000 · 5000 (più il cliente segnaposto per gli ordini ospite)

-- unit_price è lo snapshot storico: lo stesso prodotto, due prezzi nel tempo
SELECT prezzo, count(*) AS righe
FROM (SELECT DISTINCT ordine_id, riga, prezzo FROM legacy.ordini_flat WHERE sku = 'P05') d
GROUP BY prezzo
ORDER BY prezzo;
-- atteso: 20.00 × 63 · 22.00 × 37



-- =============================================================================
-- Slide 1.06 · SQL è dichiarativo; l'ordine logico
-- =============================================================================

SELECT c.name, sum(o.total) AS spesa            -- 5) SELECT
FROM demo.customers c                           -- 1) FROM
JOIN demo.orders o ON o.customer_id = c.id      --    JOIN
WHERE o.total >= 50                             -- 2) WHERE
GROUP BY c.name                                 -- 3) GROUP BY
HAVING sum(o.total) > 60                        -- 4) HAVING
ORDER BY spesa DESC                             -- 6) ORDER BY
LIMIT 1;                                        -- 7) LIMIT
-- atteso: Rossi · 150.00



-- =============================================================================
-- Slide 1.07 · Conseguenze dell'ordine logico
-- =============================================================================

-- DA SOLA: alias del SELECT nel WHERE
SELECT total * 1.22 AS total_iva FROM demo.orders WHERE total_iva > 100;
-- errore: column "total_iva" does not exist

SELECT total * 1.22 AS total_iva FROM demo.orders ORDER BY total_iva DESC;     -- ok nell'ORDER BY

-- DA SOLA: aggregato nel WHERE
SELECT customer_id FROM demo.orders WHERE sum(total) > 100 GROUP BY customer_id;
-- errore: aggregate functions are not allowed in WHERE

SELECT customer_id FROM demo.orders GROUP BY customer_id HAVING sum(total) > 100;   -- ok con HAVING

SELECT customer_id AS c, count(*) FROM demo.orders GROUP BY c;     -- alias nel GROUP BY: PostgreSQL lo accetta, non è standard

SELECT id FROM demo.orders LIMIT 2;                                -- senza ORDER BY: righe non deterministiche



-- =============================================================================
-- Slide 1.08 · JOIN
-- =============================================================================

SELECT c.name, o.id, o.total
FROM demo.customers c JOIN demo.orders o ON o.customer_id = c.id;           -- INNER: 3 righe, senza Verdi

SELECT c.name, o.id, o.total
FROM demo.customers c LEFT JOIN demo.orders o ON o.customer_id = c.id;      -- LEFT: 4 righe, Verdi con NULL

SELECT count(*) FROM demo.customers CROSS JOIN demo.orders;                 -- CROSS: 3 × 3 = 9

BEGIN;
INSERT INTO demo.orders VALUES (13, NULL, 20.00, NULL);                     -- ordine ospite
SELECT c.name, o.id, o.total
FROM demo.customers c FULL JOIN demo.orders o ON o.customer_id = c.id;      -- FULL: 5 righe, ordine 13 con cliente NULL
ROLLBACK;



-- =============================================================================
-- Slide 1.09 · Anti-join, semi-join e ON vs WHERE
-- =============================================================================

-- Anti-join: clienti senza ordini
SELECT c.name FROM demo.customers c LEFT JOIN demo.orders o ON o.customer_id = c.id WHERE o.id IS NULL;
SELECT c.name FROM demo.customers c WHERE NOT EXISTS (SELECT 1 FROM demo.orders o WHERE o.customer_id = c.id);
-- atteso: Verdi (entrambe)

-- Semi-join: clienti con almeno un ordine, senza duplicati
SELECT c.name FROM demo.customers c WHERE EXISTS (SELECT 1 FROM demo.orders o WHERE o.customer_id = c.id);
-- atteso: Rossi · Bianchi

-- Filtro nel WHERE: Verdi sparisce
SELECT c.name, o.total
FROM demo.customers c LEFT JOIN demo.orders o ON o.customer_id = c.id
WHERE o.total > 60;
-- atteso: 2 righe

-- Filtro nella ON: Verdi resta (con NULL)
SELECT c.name, o.total
FROM demo.customers c LEFT JOIN demo.orders o ON o.customer_id = c.id AND o.total > 60;
-- atteso: 3 righe



-- =============================================================================
-- Slide 1.10 · NULL: logica a tre valori
-- =============================================================================

SELECT NULL = NULL                 AS null_uguale_null,      -- NULL
       NULL IS NULL                AS is_null,               -- true
       NULL IS DISTINCT FROM NULL  AS distinct_da_null,      -- false
       (true  AND NULL)            AS t_and_null,            -- NULL
       (false AND NULL)            AS f_and_null,            -- false
       (true  OR  NULL)            AS t_or_null,             -- true
       (false OR  NULL)            AS f_or_null;             -- NULL

SELECT name FROM demo.customers WHERE city = NULL;                 -- 0 righe
SELECT name FROM demo.customers WHERE city IS NULL;                -- Verdi
SELECT name FROM demo.customers WHERE city <> 'Roma';              -- solo Bianchi
SELECT name FROM demo.customers WHERE city IS DISTINCT FROM 'Roma'; -- Bianchi e Verdi

-- CHECK è soddisfatto anche con NULL
CREATE TEMP TABLE t_check (prezzo int CHECK (prezzo > 0));
INSERT INTO t_check VALUES (NULL);                                 -- passa

-- COUNT e SUM
SELECT count(*) AS conta_righe, count(coupon) AS conta_coupon, count(DISTINCT coupon) AS coupon_distinti
FROM demo.orders;                                                  -- 3 · 1 · 1
SELECT sum(total) AS somma_vuota FROM demo.orders WHERE false;     -- NULL
SELECT coalesce(sum(total), 0) AS somma_o_zero FROM demo.orders WHERE false;   -- 0



-- =============================================================================
-- Slide 1.11 · La trappola NOT IN
-- =============================================================================

SELECT 3 NOT IN (1, 2, NULL) AS risultato;                         -- NULL (mai true)

-- Senza NULL nella sottoquery funziona
SELECT name FROM demo.customers WHERE id NOT IN (SELECT customer_id FROM demo.orders);   -- Verdi

BEGIN;
INSERT INTO demo.orders VALUES (13, NULL, 20.00, NULL);            -- un ordine ospite

SELECT name FROM demo.customers WHERE id NOT IN (SELECT customer_id FROM demo.orders);   -- 0 righe, senza errori
SELECT name FROM demo.customers c WHERE NOT EXISTS (SELECT 1 FROM demo.orders o WHERE o.customer_id = c.id);   -- Verdi
ROLLBACK;

-- Sulla tabella da 1M di ordini, NON eseguire NOT IN: solo EXPLAIN (mai ANALYZE)
EXPLAIN SELECT c.id FROM customers c WHERE c.id NOT IN (SELECT customer_id FROM orders);
-- atteso: SubPlan con costo stimato di centinaia di milioni o più (770 milioni–1,8 miliardi a seconda del server)



-- =============================================================================
-- Slide 1.12b · DDL: tabelle, tipi e vincoli
-- =============================================================================

CREATE TABLE demo.prodotti (
  sku    text PRIMARY KEY,
  nome   text NOT NULL,
  prezzo numeric(10,2) NOT NULL CHECK (prezzo >= 0),
  stato  text NOT NULL DEFAULT 'attivo' CHECK (stato IN ('attivo', 'ritirato'))
);

INSERT INTO demo.prodotti (sku, nome, prezzo) VALUES ('A1', 'Mouse', 20.00);

-- DA SOLA: una per volta, ciascuna deve dare errore
INSERT INTO demo.prodotti (sku, nome, prezzo) VALUES ('A1', 'Doppione', 5.00);     -- primary key
INSERT INTO demo.prodotti (sku, nome, prezzo) VALUES ('A2', NULL, 5.00);           -- NOT NULL
INSERT INTO demo.prodotti (sku, nome, prezzo) VALUES ('A3', 'Cavo', -1.00);        -- CHECK sul prezzo
INSERT INTO demo.prodotti (sku, nome, prezzo, stato) VALUES ('A4', 'Hub', 9.00, 'x');  -- CHECK sullo stato
-- ogni messaggio riporta il nome del vincolo (prodotti_pkey, prodotti_prezzo_check, …)

ALTER TABLE demo.prodotti ADD COLUMN peso_g int;                   -- evoluzione dello schema



-- =============================================================================
-- Slide 1.13 · DML: INSERT, UPDATE, DELETE e transazioni
-- =============================================================================

BEGIN;
INSERT INTO demo.orders VALUES (20, 2, 30.00, NULL), (21, 2, 45.00, 'SPRING');   -- più righe in un'istruzione
UPDATE demo.orders SET total = total * 2 WHERE customer_id = 2 RETURNING id, total;
SELECT count(*) FROM demo.orders;                                  -- 5
ROLLBACK;
SELECT count(*) FROM demo.orders;                                  -- 3: tutto annullato

BEGIN;
UPDATE demo.orders SET total = 0;                                  -- UPDATE senza WHERE: tocca tutte le righe
SELECT count(*) FILTER (WHERE total = 0) AS righe_azzerate FROM demo.orders;   -- 3
ROLLBACK;                                                          -- per fortuna era in transazione



-- =============================================================================
-- Slide 1.14 · SELECT: filtri, aggregazioni, sottoquery e CTE
-- =============================================================================

SELECT c.country, count(*) AS ordini, sum(o.total) AS fatturato
FROM orders o
JOIN customers c ON c.id = o.customer_id
WHERE o.status <> 'cancelled'
GROUP BY c.country
HAVING sum(o.total) > 30000000
ORDER BY fatturato DESC;
-- atteso: solo IT · 440772 ordini · 112338765.14

SELECT sum(CASE WHEN status = 'pending'   THEN 1 ELSE 0 END) AS pending,
       sum(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END) AS delivered
FROM orders;
-- atteso: 2064 · 899858

WITH piu_ordini AS (
  SELECT customer_id, count(*) AS n FROM orders GROUP BY customer_id ORDER BY n DESC, customer_id LIMIT 3
)
SELECT c.id, c.name, p.n
FROM piu_ordini p JOIN customers c ON c.id = p.customer_id
ORDER BY p.n DESC, c.id;

-- Paginazione keyset: più efficiente di OFFSET sulle tabelle grandi
SELECT id, created_at FROM orders WHERE id > 500000 ORDER BY id LIMIT 5;



-- =============================================================================
-- Slide 1.15 · I due dataset del corso
-- =============================================================================

SELECT 'legacy.ordini_flat' AS tabella, count(*) AS righe FROM legacy.ordini_flat
UNION ALL SELECT 'public.customers',   count(*) FROM public.customers
UNION ALL SELECT 'public.orders',      count(*) FROM public.orders
UNION ALL SELECT 'public.order_items', count(*) FROM public.order_items;
-- atteso: 5010 · 100000 · 1000000 · 2000000

SELECT status, count(*), round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS percentuale
FROM orders GROUP BY status ORDER BY count(*) DESC;
-- atteso: delivered 90,0 · shipped 6,0 · paid 3,0 · cancelled 0,8 · pending 0,2



-- =============================================================================
-- Slide 2.01 · PostgreSQL: il motore e il viaggio di una query
-- =============================================================================

SELECT version();

SELECT pg_backend_pid() AS il_mio_processo;                 -- un processo per connessione

SELECT pid, backend_type, state, left(query, 40) AS query   -- i processi del server
FROM pg_stat_activity
ORDER BY backend_type, pid;



-- =============================================================================
-- Slide 2.02 · Processi e memoria
-- =============================================================================

SELECT backend_type, count(*) FROM pg_stat_activity GROUP BY backend_type ORDER BY backend_type;
-- atteso: client backend, autovacuum launcher, background writer, checkpointer, walwriter, …

SELECT name, setting, unit, context
FROM pg_settings
WHERE name IN ('shared_buffers', 'effective_cache_size', 'work_mem', 'maintenance_work_mem', 'max_connections')
ORDER BY name;
-- context: postmaster = serve il riavvio · user = si cambia con SET

-- work_mem è per nodo: con poca memoria l'ordinamento finisce su disco
SET work_mem = '64kB';
EXPLAIN (ANALYZE) SELECT id, total FROM orders ORDER BY total;
-- atteso: Sort Method: external merge  Disk: …

SET work_mem = '256MB';
EXPLAIN (ANALYZE) SELECT id, total FROM orders ORDER BY total;
-- atteso: Sort Method: quicksort  Memory: …

RESET work_mem;



-- =============================================================================
-- Slide 2.03 · Storage e WAL
-- =============================================================================

SHOW block_size;                                            -- 8192

SELECT relname, relpages, reltuples::bigint AS righe_stimate,
       pg_size_pretty(pg_relation_size(oid)) AS heap
FROM pg_class
WHERE relnamespace = 'public'::regnamespace AND relname IN ('customers', 'orders', 'order_items')
ORDER BY relname;
-- atteso: orders circa 15.360 pagine, 120 MB

SELECT ctid, id FROM orders WHERE id IN (1, 2, 3, 100000) ORDER BY id;     -- (pagina, posizione)

SELECT pg_relation_filepath('orders');                      -- il file su disco

SELECT c.relname, t.relname AS tabella_toast                -- TOAST: tabella di supporto
FROM pg_class c LEFT JOIN pg_class t ON t.oid = c.reltoastrelid
WHERE c.relnamespace = 'public'::regnamespace AND c.relname = 'orders';

-- WAL generato da un inserimento (tabella normale contro UNLOGGED)
CREATE TEMP TABLE lsn_prima AS SELECT pg_current_wal_lsn() AS lsn;
CREATE TABLE demo.con_wal AS SELECT g AS id, repeat('x', 100) AS pad FROM generate_series(1, 100000) g;
SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), lsn)) AS wal_normale FROM lsn_prima;

CREATE TEMP TABLE lsn_prima2 AS SELECT pg_current_wal_lsn() AS lsn;
CREATE UNLOGGED TABLE demo.senza_wal AS SELECT g AS id, repeat('x', 100) AS pad FROM generate_series(1, 100000) g;
SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), lsn)) AS wal_unlogged FROM lsn_prima2;
-- atteso: circa 15 MB contro circa 16 kB



-- =============================================================================
-- Slide 2.04 · Tipi di dato: dove PostgreSQL fa la differenza
-- =============================================================================

SELECT 0.1::float8  + 0.2::float8  = 0.3::float8  AS float_uguale,         -- false
       0.1::numeric + 0.2::numeric = 0.3::numeric AS numeric_uguale;       -- true

-- timestamptz memorizza un istante; timestamp ignora l'offset
SELECT '2026-01-01 12:00+02'::timestamptz AS con_fuso,
       '2026-01-01 12:00+02'::timestamp   AS senza_fuso;

SET timezone TO 'UTC';          SELECT '2026-01-01 12:00+02'::timestamptz AS in_utc;
SET timezone TO 'Europe/Rome';  SELECT '2026-01-01 12:00+02'::timestamptz AS a_roma;
RESET timezone;

SELECT pg_column_size(gen_random_uuid()) AS uuid_byte, pg_column_size(gen_random_uuid()::text) AS testo_byte;
-- atteso: 16 · 40

-- Le sequenze non sono transazionali: ROLLBACK consuma comunque un valore
CREATE TEMP TABLE t_id (id int GENERATED ALWAYS AS IDENTITY, v text);
BEGIN; INSERT INTO t_id (v) VALUES ('a'); ROLLBACK;
INSERT INTO t_id (v) VALUES ('b') RETURNING id;                            -- 2: c'è un buco

-- Array, jsonb, range
SELECT ARRAY['gift', 'express']                                    AS array_,
       '{"canale": "app", "coupon": "SPRING"}'::jsonb              AS documento,
       tstzrange('2026-10-20 09:00', '2026-10-20 11:00')           AS intervallo;



-- =============================================================================
-- Slide 2.05 · Il dialetto PostgreSQL
-- =============================================================================

BEGIN;
INSERT INTO demo.customers (id, name, city) VALUES (4, 'Neri', 'Torino') RETURNING id, name;   -- RETURNING

INSERT INTO demo.customers (id, name, city) VALUES (1, 'Rossi M.', 'Roma')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name
RETURNING id, name, (xmax = 0) AS inserito;                                -- false: era un aggiornamento

INSERT INTO demo.customers (id, name, city) VALUES (1, 'X', 'Y')
ON CONFLICT (id) DO NOTHING RETURNING id;                                  -- zero righe

MERGE INTO demo.customers c                                                -- PG 15+
USING (VALUES (2, 'Bianchi SpA', 'Milano')) v (id, name, city) ON c.id = v.id
WHEN MATCHED THEN UPDATE SET name = v.name
WHEN NOT MATCHED THEN INSERT VALUES (v.id, v.name, v.city);
ROLLBACK;

-- DISTINCT ON: l'ordine più recente per cliente
SELECT DISTINCT ON (customer_id) customer_id, id, created_at, total
FROM orders WHERE customer_id <= 3
ORDER BY customer_id, created_at DESC, id DESC;

-- FILTER: aggregato condizionale
SELECT count(*) FILTER (WHERE status = 'pending') AS pending,
       count(*) FILTER (WHERE status = 'paid')    AS paid
FROM orders;
-- atteso: 2064 · 29835

-- generate_series: anche i giorni senza ordini
SELECT g::date AS giorno, count(o.id) AS ordini
FROM generate_series('2026-12-12'::date, '2026-12-17'::date, interval '1 day') g
LEFT JOIN orders o ON o.created_at >= g AND o.created_at < g + interval '1 day'
GROUP BY g ORDER BY g;
-- atteso: 2880 · 2880 · 641 · 0 · 0 · 0

-- UPDATE ... FROM
BEGIN;
UPDATE orders o SET status = 'cancelled'
FROM customers c
WHERE c.id = o.customer_id AND c.country = 'ES' AND o.status = 'pending';  -- UPDATE 232
ROLLBACK;

-- CTE: il planner la "inlina" (da PG 12) oppure la materializza se richiesto
EXPLAIN WITH c AS (SELECT * FROM customers WHERE id = 500) SELECT * FROM c;                 -- Index Scan diretto
EXPLAIN WITH c AS MATERIALIZED (SELECT * FROM customers WHERE id = 500) SELECT * FROM c;     -- compare CTE Scan



-- =============================================================================
-- Slide 2.06 · DDL transazionale, vincoli e schemi in PostgreSQL
-- =============================================================================

BEGIN;
CREATE TABLE demo.prova_ddl (id int);
SELECT to_regclass('demo.prova_ddl') AS dentro_la_transazione;             -- demo.prova_ddl
ROLLBACK;
SELECT to_regclass('demo.prova_ddl') AS dopo_il_rollback;                  -- NULL

SHOW search_path;
SELECT current_schema();

-- La foreign key NON crea l'indice: su orders c'è solo la primary key
SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'orders';
-- atteso (dump appena caricato): orders_pkey

SELECT conname, contype FROM pg_constraint WHERE conrelid = 'public.orders'::regclass ORDER BY conname;

-- DA SOLA: il messaggio riporta il nome del vincolo
INSERT INTO customers (email, name, country) VALUES ('user10@example.com', 'Doppione', 'IT');
-- errore: duplicate key value violates unique constraint "customers_email_key"



-- =============================================================================
-- Slide 2.07 · Il planner: dal testo al piano
-- =============================================================================

EXPLAIN SELECT * FROM customers WHERE id = 500;
-- atteso: Index Scan using customers_pkey … (cost=0.29..8.31 rows=1 …)

EXPLAIN SELECT country, count(*) FROM customers GROUP BY country;

SELECT relname, reltuples::bigint AS righe_stimate, relpages     -- le statistiche che usa il planner
FROM pg_class
WHERE relnamespace = 'public'::regnamespace AND relname IN ('customers', 'orders');

-- NOT EXISTS diventa un anti-join; NOT IN no (solo EXPLAIN, mai ANALYZE)
EXPLAIN SELECT c.id FROM customers c WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id);
-- atteso: Hash Right Anti Join (da PG 16; prima Hash Anti Join)
EXPLAIN SELECT c.id FROM customers c WHERE c.id NOT IN (SELECT customer_id FROM orders);
-- atteso: SubPlan, costo stimato di centinaia di milioni o più (770 milioni–1,8 miliardi a seconda del server)



-- =============================================================================
-- Slide 2.08 · MVCC: versioni di riga
-- =============================================================================

CREATE TABLE demo.mvcc (id int PRIMARY KEY, val text);
INSERT INTO demo.mvcc VALUES (1, 'a'), (2, 'a');

SELECT xmin, xmax, ctid, * FROM demo.mvcc;                  -- stesso xmin, xmax = 0, ctid (0,1) e (0,2)

UPDATE demo.mvcc SET val = 'b' WHERE id = 1;
SELECT xmin, xmax, ctid, * FROM demo.mvcc;                  -- riga 1: nuovo xmin e nuovo ctid (0,3)

BEGIN;
UPDATE demo.mvcc SET val = 'c' WHERE id = 2;
SELECT xmin, xmax, ctid, * FROM demo.mvcc WHERE id = 2;     -- versione nuova
ROLLBACK;
SELECT xmin, xmax, ctid, * FROM demo.mvcc WHERE id = 2;     -- torna la vecchia, con xmax ≠ 0: non è cancellata

BEGIN;
DELETE FROM demo.mvcc WHERE id = 2;
SELECT count(*) FROM demo.mvcc;                             -- 1 (per questa transazione)
ROLLBACK;
SELECT count(*) FROM demo.mvcc;                             -- 2: nessun lavoro fisico da disfare



-- =============================================================================
-- Slide 2.09 · Snapshot e visibilità; due sessioni sulla stessa riga
-- =============================================================================

-- Snapshot: chi è già confermato, in questo istante
BEGIN;
SELECT pg_current_snapshot();                               -- xmin:xmax:xip_list
SELECT pg_current_xact_id() AS la_mia_transazione;
COMMIT;

-- Due sessioni, A e B (demo.mvcc dalla slide 2.08)
--   [A] BEGIN; UPDATE demo.mvcc SET val = 'A' WHERE id = 1;                  -- senza COMMIT
--   [B] SELECT xmin, xmax, ctid, * FROM demo.mvcc WHERE id = 1;              -- vede il valore vecchio, xmax = A
--   [B] UPDATE demo.mvcc SET val = 'B' WHERE id = 1;                         -- SI BLOCCA (due scrittori)
--   [A] COMMIT;                                                              -- B si sblocca
--   [B] SELECT xmin, xmax, ctid, * FROM demo.mvcc WHERE id = 1;              -- vede la versione nuova di B
--   Variante: al posto del COMMIT di A, ROLLBACK → la vecchia versione resta valida per tutti.



-- =============================================================================
-- Slide 2.10 · Il prezzo dell'MVCC
-- =============================================================================

CREATE TABLE demo.dead (id int PRIMARY KEY, val text) WITH (autovacuum_enabled = false);
INSERT INTO demo.dead SELECT g, 'v' FROM generate_series(1, 100000) g;
UPDATE demo.dead SET val = 'w';                             -- ogni riga ha ora due versioni

SELECT pg_stat_force_next_flush();                          -- aggiorna subito i contatori (PG 15+)
SELECT n_live_tup, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'dead';
-- atteso: 100000 vive · 100000 morte

VACUUM demo.dead;
SELECT n_live_tup, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'dead';
-- atteso: n_dead_tup a 0 (i contatori possono aggiornarsi dopo qualche secondo)



-- =============================================================================
-- Slide 2.11 · Transazioni: ACID, errori, SAVEPOINT
-- =============================================================================

-- Un errore manda la transazione in stato "aborted"
BEGIN;
INSERT INTO demo.prodotti (sku, nome, prezzo) VALUES ('B1', 'Ok', 1.00);
INSERT INTO demo.prodotti (sku, nome, prezzo) VALUES ('B2', 'Errore', -5.00);     -- errore: prodotti_prezzo_check
SELECT 1;                                                                          -- errore: transaction is aborted
ROLLBACK;
SELECT count(*) FROM demo.prodotti WHERE sku IN ('B1', 'B2');                      -- 0: tutto annullato

-- Con un SAVEPOINT si annulla solo la parte sbagliata
BEGIN;
INSERT INTO demo.prodotti (sku, nome, prezzo) VALUES ('B1', 'Ok', 1.00);
SAVEPOINT dopo_b1;
INSERT INTO demo.prodotti (sku, nome, prezzo) VALUES ('B2', 'Errore', -5.00);     -- errore
ROLLBACK TO dopo_b1;
SELECT 1;                                                                          -- la transazione è di nuovo utilizzabile
INSERT INTO demo.prodotti (sku, nome, prezzo) VALUES ('B3', 'Ok anche questo', 2.00);
COMMIT;
SELECT sku FROM demo.prodotti ORDER BY sku;                                        -- A1 · B1 · B3



-- =============================================================================
-- Slide 2.12 · Livelli di isolamento e anomalie
-- =============================================================================

CREATE TABLE demo.accounts (id int PRIMARY KEY, balance int NOT NULL CHECK (balance >= 0));
INSERT INTO demo.accounts VALUES (1, 100), (2, 100);

SHOW default_transaction_isolation;                         -- read committed
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT current_setting('transaction_isolation');            -- repeatable read
COMMIT;

-- Non-repeatable read: Read Committed contro Repeatable Read (due sessioni)
--   [A] BEGIN;                                                    -- Read Committed
--   [A] SELECT balance FROM demo.accounts WHERE id = 1;           -- 100
--   [B] UPDATE demo.accounts SET balance = 150 WHERE id = 1;
--   [A] SELECT balance FROM demo.accounts WHERE id = 1;           -- 150: lo snapshot è per istruzione
--   [A] COMMIT;
--   (ripristina: UPDATE demo.accounts SET balance = 100 WHERE id = 1;)
--   [A] BEGIN ISOLATION LEVEL REPEATABLE READ;
--   [A] SELECT balance FROM demo.accounts WHERE id = 1;           -- 100
--   [B] UPDATE demo.accounts SET balance = 150 WHERE id = 1;
--   [A] SELECT balance FROM demo.accounts WHERE id = 1;           -- 100: lo snapshot è per transazione
--   [A] COMMIT;
-- Phantom: con A in Repeatable Read, un INSERT di B non cambia il count(*) di A (in PostgreSQL).



-- =============================================================================
-- Slide 2.13 · Lost update e write skew
-- =============================================================================

-- Prima di ogni prova: UPDATE demo.accounts SET balance = 100;
-- Lost update (il bug): A e B leggono 100 e calcolano nell'applicazione
--   [A] BEGIN; SELECT balance FROM demo.accounts WHERE id = 1;                -- 100
--   [B] BEGIN; SELECT balance FROM demo.accounts WHERE id = 1;                -- 100
--   [A] UPDATE demo.accounts SET balance = 150 WHERE id = 1; COMMIT;          -- +50
--   [B] UPDATE demo.accounts SET balance = 130 WHERE id = 1; COMMIT;          -- +30 (si sblocca dopo il COMMIT di A)
--   [B] SELECT balance FROM demo.accounts WHERE id = 1;                       -- 130 invece di 180
-- Correzione 1: aggiornamento atomico
--   [A] UPDATE demo.accounts SET balance = balance + 50 WHERE id = 1; COMMIT;
--   [B] UPDATE demo.accounts SET balance = balance + 30 WHERE id = 1; COMMIT;  -- 180
-- Correzione 2: SELECT … FOR UPDATE; correzione 3: Repeatable Read e retry
--   [B] (in REPEATABLE READ) UPDATE … → ERROR: could not serialize access due to concurrent update (40001)

CREATE TABLE demo.oncall (doctor text PRIMARY KEY, on_call boolean NOT NULL);
INSERT INTO demo.oncall VALUES ('Anna', true), ('Bruno', true);

-- Write skew: regola "almeno un medico di turno"
--   [A] BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT count(*) FROM demo.oncall WHERE on_call;   -- 2
--   [B] BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT count(*) FROM demo.oncall WHERE on_call;   -- 2
--   [A] UPDATE demo.oncall SET on_call = false WHERE doctor = 'Anna';  COMMIT;
--   [B] UPDATE demo.oncall SET on_call = false WHERE doctor = 'Bruno'; COMMIT;                   -- riesce: zero medici di turno
-- Con SERIALIZABLE al posto di REPEATABLE READ, uno dei due COMMIT fallisce:
--   ERROR: could not serialize access due to read/write dependencies among transactions (40001)
--   Ritentando, la transazione vede 1 medico di turno e non procede.



-- =============================================================================
-- Slide 2.14 · Lock espliciti e deadlock
-- =============================================================================

CREATE TABLE demo.jobs (id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, payload text, status text NOT NULL DEFAULT 'new');
INSERT INTO demo.jobs (payload) SELECT 'job ' || g FROM generate_series(1, 5) g;

-- Il lock di riga tiene anche un lock di tabella debole
BEGIN;
SELECT id FROM demo.accounts WHERE id = 1 FOR UPDATE;
SELECT mode FROM pg_locks
WHERE pid = pg_backend_pid() AND locktype = 'relation' AND relation = 'demo.accounts'::regclass;   -- RowShareLock
ROLLBACK;

-- Coda di lavori: prende il primo job libero senza attendere gli altri
UPDATE demo.jobs SET status = 'running'
WHERE id = (SELECT id FROM demo.jobs WHERE status = 'new' ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED)
RETURNING id, payload;                                      -- job 1

-- Due sessioni, A e B
--   [A] BEGIN; SELECT * FROM demo.accounts WHERE id = 1 FOR UPDATE;
--   [B] SELECT * FROM demo.accounts WHERE id = 1 FOR UPDATE NOWAIT;
--       → ERROR: could not obtain lock on row in relation "accounts" (55P03)
--   [B] SET lock_timeout = '500ms'; SELECT * FROM demo.accounts WHERE id = 1 FOR UPDATE;
--       → ERROR: canceling statement due to lock timeout (55P03)
--   [B] SELECT * FROM demo.accounts WHERE id = 1 FOR UPDATE;                 -- attende (lock_timeout azzerato)
--   [C] chi blocca chi:
--       SELECT pid, pg_blocking_pids(pid) AS bloccato_da, wait_event_type, wait_event, left(query, 40)
--       FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0;
--   [A] ROLLBACK;                                                            -- B prosegue
--
--   SKIP LOCKED con due consumatori:
--   [A] BEGIN; SELECT id FROM demo.jobs WHERE status = 'new' ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED;   -- job 2
--   [B] BEGIN; SELECT id FROM demo.jobs WHERE status = 'new' ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED;   -- job 3, senza attese
--
--   Deadlock (ordine opposto):
--   [A] BEGIN; UPDATE demo.accounts SET balance = balance WHERE id = 1;
--   [B] BEGIN; UPDATE demo.accounts SET balance = balance WHERE id = 2;
--   [A] UPDATE demo.accounts SET balance = balance WHERE id = 2;             -- attende B
--   [B] UPDATE demo.accounts SET balance = balance WHERE id = 1;             -- attende A: dopo circa 1 s
--       → una delle due: ERROR: deadlock detected (40P01); l'altra prosegue
--   Correzione: stesso ordine di accesso (ORDER BY id FOR UPDATE) in entrambe:
--   [A]/[B] SELECT id FROM demo.accounts WHERE id IN (1, 2) ORDER BY id FOR UPDATE;



-- =============================================================================
-- Slide 2.15 · Retry nel codice
-- =============================================================================

-- Il retry vero sta nel CLIENT, intorno all'intera transazione: qui ne mostriamo la logica
-- simulando due errori di serializzazione (SQLSTATE 40001) prima del successo.
DO $$
DECLARE
  tentativo int := 0;
BEGIN
  LOOP
    tentativo := tentativo + 1;
    BEGIN
      IF tentativo < 3 THEN
        RAISE EXCEPTION 'conflitto simulato' USING ERRCODE = '40001';
      END IF;
      RAISE NOTICE 'riuscito al tentativo %', tentativo;
      EXIT;
    EXCEPTION WHEN serialization_failure OR deadlock_detected THEN
      IF tentativo >= 5 THEN RAISE; END IF;                  -- limite di tentativi
      RAISE NOTICE 'tentativo % fallito (40001/40P01): riprovo', tentativo;
      PERFORM pg_sleep(0.05 * tentativo);                    -- attesa crescente
    END;
  END LOOP;
END $$;
-- atteso (console output): due tentativi falliti, riuscito al tentativo 3
-- Ritentare SOLO su 40001 e 40P01, l'INTERA transazione; effetti esterni (email, HTTP) fuori dal ciclo.



-- =============================================================================
-- Slide 3.02 · Indice B-Tree: com'è fatto
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pageinspect;

SELECT i.indexname,
       (bt_metap(i.indexname)).level + 1 AS livelli,
       c.relpages AS pagine
FROM pg_indexes i
JOIN pg_class c ON c.relname = i.indexname AND c.relnamespace = 'public'::regnamespace
WHERE i.schemaname = 'public' AND i.indexname = 'orders_pkey';
-- atteso: 3 livelli · circa 2745 pagine (per 1 milione di righe)

EXPLAIN SELECT * FROM orders WHERE id BETWEEN 100 AND 110;        -- intervallo: scorre le foglie
EXPLAIN SELECT id FROM orders ORDER BY id LIMIT 5;                -- ORDER BY + LIMIT: nessun Sort

-- LIKE 'abc%' usa un B-Tree solo con collation C oppure text_pattern_ops
SELECT datcollate, datctype FROM pg_database WHERE datname = current_database();   -- la collation del database
BEGIN;
CREATE INDEX demo_name_default ON customers (name);
EXPLAIN SELECT id FROM customers WHERE name LIKE 'Customer 1234%';
-- atteso con collation diversa da C (anche C.UTF-8): Seq Scan
CREATE INDEX demo_name_pattern ON customers (name text_pattern_ops);
EXPLAIN SELECT id FROM customers WHERE name LIKE 'Customer 1234%';
-- atteso: usa demo_name_pattern
ROLLBACK;



-- =============================================================================
-- Slide 3.03 · Selettività: indice, bitmap o scansione
-- =============================================================================

BEGIN;
CREATE INDEX demo_status ON orders (status);

EXPLAIN SELECT sum(total) FROM orders WHERE status = 'pending';      -- 0,2%: usa l'indice
EXPLAIN SELECT sum(total) FROM orders WHERE status = 'paid';         -- 3%: via di mezzo
EXPLAIN SELECT sum(total) FROM orders WHERE status = 'delivered';    -- 90%: Seq Scan
ROLLBACK;
-- le soglie dipendono da dimensione della tabella, distribuzione fisica e random_page_cost



-- =============================================================================
-- Slide 3.04 · Indici compositi e parziali
-- =============================================================================

BEGIN;
DROP INDEX IF EXISTS idx_orders_customer_created, idx_orders_pending, idx_orders_customer;   -- annullati dal ROLLBACK

CREATE INDEX demo_cust ON orders (customer_id);
EXPLAIN SELECT * FROM orders WHERE customer_id = 4242 ORDER BY created_at DESC LIMIT 3;
-- atteso: c'è un Sort (top-N heapsort)

CREATE INDEX demo_comp ON orders (customer_id, created_at);
EXPLAIN SELECT * FROM orders WHERE customer_id = 4242 ORDER BY created_at DESC LIMIT 3;
-- atteso: Index Scan Backward using demo_comp, nessun Sort

EXPLAIN SELECT * FROM orders WHERE created_at >= '2026-12-01' AND created_at < '2026-12-02';
-- solo la seconda colonna: Seq Scan (PG 18: skip scan solo se la prima colonna ha pochi valori distinti)

CREATE INDEX demo_part ON orders (created_at) WHERE status = 'pending';
EXPLAIN SELECT id FROM orders WHERE status = 'pending' ORDER BY created_at DESC LIMIT 10;
-- atteso: Index Scan Backward using demo_part

SELECT pg_size_pretty(pg_relation_size('demo_cust')) AS solo_customer_id,
       pg_size_pretty(pg_relation_size('demo_comp')) AS composito,
       pg_size_pretty(pg_relation_size('demo_part')) AS parziale;
-- atteso: circa 9 MB · 30 MB · 64 kB

-- L'indice parziale non viene usato con uno statement parametrizzato e piano generico
PREPARE q (text) AS SELECT id FROM orders WHERE status = $1 ORDER BY created_at DESC LIMIT 10;
SET plan_cache_mode = force_generic_plan;
EXPLAIN EXECUTE q ('pending');                                    -- non usa demo_part
SET plan_cache_mode = force_custom_plan;
EXPLAIN EXECUTE q ('pending');                                    -- usa demo_part
DEALLOCATE q;
ROLLBACK;



-- =============================================================================
-- Slide 3.05 · Il costo degli indici
-- =============================================================================

-- Indici mai usati: idx_scan = 0
-- (orders_pkey ha già circa 2 milioni di scansioni: sono i controlli della FK di order_items durante il caricamento)
SELECT indexrelid::regclass AS indice, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) AS dimensione
FROM pg_stat_user_indexes
WHERE relid = 'public.orders'::regclass
ORDER BY idx_scan;

-- Il costo in scrittura: stessa INSERT con 0 e con 3 indici (durate nella console output)
CREATE TABLE demo.w0 (id int, a int, b int, c int);
CREATE TABLE demo.w3 (id int, a int, b int, c int);
CREATE INDEX ON demo.w3 (a);
CREATE INDEX ON demo.w3 (b);
CREATE INDEX ON demo.w3 (c);

DO $$
DECLARE t0 timestamptz;
BEGIN
  t0 := clock_timestamp();
  INSERT INTO demo.w0 SELECT g, (random() * 1e6)::int, (random() * 1e6)::int, (random() * 1e6)::int
  FROM generate_series(1, 300000) g;
  RAISE NOTICE 'senza indici: % ms', round(extract(epoch FROM clock_timestamp() - t0) * 1000);

  t0 := clock_timestamp();
  INSERT INTO demo.w3 SELECT g, (random() * 1e6)::int, (random() * 1e6)::int, (random() * 1e6)::int
  FROM generate_series(1, 300000) g;
  RAISE NOTICE 'con 3 indici: % ms', round(extract(epoch FROM clock_timestamp() - t0) * 1000);
END $$;
-- atteso: la seconda è da 2 a 4 volte più lenta (dipende dalla macchina)

-- CREATE INDEX CONCURRENTLY: fuori transazione
CREATE INDEX CONCURRENTLY demo_cic ON orders (total);
SELECT indisvalid FROM pg_index WHERE indexrelid = 'demo_cic'::regclass;      -- true
DROP INDEX CONCURRENTLY demo_cic;

-- DA SOLA: dentro una transazione non si può
BEGIN;
CREATE INDEX CONCURRENTLY demo_cic ON orders (total);
-- errore: CREATE INDEX CONCURRENTLY cannot run inside a transaction block
ROLLBACK;

-- Se fallisce, lascia un indice INVALID da eliminare
CREATE TABLE demo.dup (a int);
INSERT INTO demo.dup VALUES (1), (1);
-- DA SOLA: errore perché i dati hanno duplicati
CREATE UNIQUE INDEX CONCURRENTLY demo_dup_u ON demo.dup (a);
SELECT indexrelid::regclass AS indice, indisvalid FROM pg_index WHERE indrelid = 'demo.dup'::regclass;   -- false



-- =============================================================================
-- Slide 3.06 · Cos'è un piano di esecuzione
-- =============================================================================

EXPLAIN SELECT count(*) FROM orders WHERE status = 'pending';             -- stimato, non esegue
EXPLAIN (ANALYZE) SELECT count(*) FROM orders WHERE status = 'pending';   -- esegue: tempi e righe reali

-- Con DML, EXPLAIN ANALYZE modifica i dati: in transazione e ROLLBACK
BEGIN;
EXPLAIN (ANALYZE, BUFFERS) UPDATE orders SET status = 'paid' WHERE id = 1000;
ROLLBACK;
SELECT status FROM orders WHERE id = 1000;                                -- invariato

SELECT name, setting FROM pg_settings
WHERE name IN ('seq_page_cost', 'random_page_cost', 'cpu_tuple_cost', 'cpu_operator_cost')
ORDER BY name;
-- atteso: 1 · 4 · 0.01 · 0.0025 (i costi sono unità arbitrarie, non millisecondi)



-- =============================================================================
-- Slide 3.07 · Leggere un nodo: stima contro realtà
-- =============================================================================

BEGIN;
CREATE INDEX demo_cust ON orders (customer_id);

EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE customer_id = 4242;
-- atteso: Bitmap Heap Scan · rows=11 stimate, rows=9 reali · Heap Blocks: exact=9
-- prima esecuzione: Buffers shared read; ripetendo: tutti shared hit

EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id FROM customers c JOIN orders o ON o.customer_id = c.id WHERE c.id IN (1, 2, 3);
-- atteso: nodo interno con loops=3: tempo e righe sono medie per ciclo, il totale è valore × loops
ROLLBACK;



-- =============================================================================
-- Slide 3.08 · Statistiche e stime
-- =============================================================================

SELECT attname, n_distinct, round(correlation::numeric, 2) AS correlazione, null_frac
FROM pg_stats
WHERE schemaname = 'public' AND tablename = 'orders' AND attname IN ('status', 'customer_id', 'created_at');
-- created_at: correlazione 1 · customer_id: n_distinct positivo (circa 94.000)

SELECT most_common_vals, most_common_freqs
FROM pg_stats
WHERE schemaname = 'public' AND tablename = 'orders' AND attname = 'status';

-- Tabella mai analizzata: stima di default
CREATE TABLE demo.est (id int, grp int) WITH (autovacuum_enabled = false);
INSERT INTO demo.est SELECT g, g % 10 FROM generate_series(1, 100000) g;
EXPLAIN (ANALYZE) SELECT * FROM demo.est WHERE grp = 3;       -- rows ≈ 500 stimate, 10000 reali
ANALYZE demo.est;
EXPLAIN (ANALYZE) SELECT * FROM demo.est WHERE grp = 3;       -- rows ≈ 10000

-- Colonne correlate: il planner assume indipendenza
CREATE TABLE demo.cs (a int, b int);
INSERT INTO demo.cs SELECT g % 10, g % 10 FROM generate_series(1, 10000) g;
ANALYZE demo.cs;
EXPLAIN SELECT * FROM demo.cs WHERE a = 1 AND b = 1;          -- stima 100 (reali 1000)
CREATE STATISTICS demo_cs_st (dependencies) ON a, b FROM demo.cs;
ANALYZE demo.cs;
EXPLAIN SELECT * FROM demo.cs WHERE a = 1 AND b = 1;          -- stima 1000

-- Espressioni su campi JSON: nessuna statistica
EXPLAIN SELECT count(*) FROM orders WHERE attrs->>'channel' = 'app';     -- rows ≈ 5000 (reali 333.334)

SHOW default_statistics_target;                                -- 100



-- =============================================================================
-- Slide 3.09 · Metodi di accesso
-- =============================================================================

EXPLAIN (ANALYZE) SELECT count(*) FROM orders WHERE status = 'delivered';     -- Seq Scan
EXPLAIN (ANALYZE) SELECT * FROM orders WHERE id = 500000;                     -- Index Scan (primary key)
EXPLAIN (ANALYZE) SELECT id FROM orders WHERE id BETWEEN 100 AND 200;         -- Index Only Scan
-- Heap Fetches ≈ 0 dopo VACUUM; su una tabella appena caricata il planner può preferire altro

BEGIN;
CREATE INDEX demo_cust ON orders (customer_id);
EXPLAIN (ANALYZE) SELECT id FROM orders WHERE customer_id BETWEEN 100 AND 110;   -- Bitmap Index + Bitmap Heap Scan

-- Bitmap lossy: poca work_mem
SET enable_seqscan = off;
SET enable_indexscan = off;
SET work_mem = '64kB';
EXPLAIN (ANALYZE) SELECT id FROM orders WHERE customer_id BETWEEN 1 AND 3000;    -- Heap Blocks: exact=… lossy=…
RESET enable_seqscan;
RESET enable_indexscan;
RESET work_mem;

-- BitmapOr: due indici combinati
CREATE INDEX demo_tags ON orders USING gin (tags);
EXPLAIN SELECT id FROM orders WHERE customer_id = 7 OR tags @> ARRAY['vip'];     -- BitmapOr
ROLLBACK;

-- Parallelo
SET max_parallel_workers_per_gather = 2;
EXPLAIN (ANALYZE) SELECT count(*) FROM orders WHERE status = 'delivered';
-- atteso: Gather · Workers Planned: 2 · Workers Launched: 2 · Parallel Seq Scan
SET max_parallel_workers_per_gather = 0;



-- =============================================================================
-- Slide 3.10 · Algoritmi di join
-- =============================================================================

BEGIN;
CREATE INDEX demo_cust ON orders (customer_id);
EXPLAIN (ANALYZE) SELECT c.name, o.id FROM customers c JOIN orders o ON o.customer_id = c.id WHERE c.id = 4242;
-- atteso: Nested Loop (poche righe esterne + indice sull'interna)
ROLLBACK;

EXPLAIN (ANALYZE) SELECT c.country, count(*) FROM customers c JOIN orders o ON o.customer_id = c.id GROUP BY c.country;
-- atteso: Hash Join · Batches: 1

SET work_mem = '1MB';
EXPLAIN (ANALYZE) SELECT c.country, count(*) FROM customers c JOIN orders o ON o.customer_id = c.id GROUP BY c.country;
-- atteso: Batches: 4 (la hash table non sta in work_mem)
RESET work_mem;

-- Merge Join: solo forzato, per diagnosi
SET enable_hashjoin = off;
SET enable_nestloop = off;
EXPLAIN SELECT c.id FROM customers c JOIN orders o ON o.customer_id = c.id;
RESET enable_hashjoin;
RESET enable_nestloop;

-- Anti-join: NOT EXISTS sì, NOT IN no (solo EXPLAIN, mai ANALYZE)
EXPLAIN SELECT c.id FROM customers c WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id);
EXPLAIN SELECT c.id FROM customers c WHERE c.id NOT IN (SELECT customer_id FROM orders);



-- =============================================================================
-- Slide 3.11 · DML e il costo nascosto delle FK
-- =============================================================================

BEGIN;
CREATE INDEX demo_cust ON orders (customer_id);
INSERT INTO customers (email, name, country) VALUES ('fk1@example.com', 'FK 1', 'IT'), ('fk2@example.com', 'FK 2', 'IT');

EXPLAIN (ANALYZE) DELETE FROM customers WHERE email = 'fk1@example.com';
-- atteso: Trigger for constraint orders_customer_id_fkey: frazioni di millisecondo

DROP INDEX demo_cust;
DROP INDEX IF EXISTS idx_orders_customer_created, idx_orders_customer;   -- se il laboratorio li ha creati

EXPLAIN (ANALYZE) DELETE FROM customers WHERE email = 'fk2@example.com';
-- atteso: lo stesso trigger, da decine a centinaia di millisecondi (scansione di tutta orders)
ROLLBACK;



-- =============================================================================
-- Slide 3.12 · Metodo di tuning
-- =============================================================================

EXPLAIN (GENERIC_PLAN) SELECT * FROM orders WHERE id = $1;                -- PG 16+: query con parametri

EXPLAIN (SETTINGS) SELECT count(*) FROM orders;                           -- mostra i parametri cambiati nella sessione

-- Misura a caldo: eseguire DUE volte e confrontare read e hit
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM orders WHERE id BETWEEN 300000 AND 330000;
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM orders WHERE id BETWEEN 300000 AND 330000;
-- atteso: la prima volta Buffers: shared read (dal disco o dal sistema operativo); la seconda solo shared hit
-- Attenzione: una Seq Scan di una tabella grande usa un piccolo buffer ad anello, quindi anche alla
-- seconda esecuzione mostra ancora shared read: il confronto hit/read vale per le scansioni con indice.



-- =============================================================================
-- Slide 3.13 · pg_stat_statements: perché e come
-- =============================================================================

-- CREATE EXTENSION funziona anche prima del riavvio…
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SHOW shared_preload_libraries;

-- …ma la vista dà errore finché il modulo non è precaricato:
-- SELECT count(*) FROM pg_stat_statements;
--   → ERROR: pg_stat_statements must be loaded via shared_preload_libraries

-- Abilitazione:
--   ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';   -- sostituisce l'intero valore
--   [terminale host]  docker compose restart db
--   [DBeaver]         Invalidate/Reconnect
--   SHOW shared_preload_libraries;
-- Le opzioni -c all'avvio vincono su ALTER SYSTEM; CREATE EXTENSION va fatto in ogni database.



-- =============================================================================
-- Slide 3.14 · Leggere la vista
-- =============================================================================

SELECT pg_stat_statements_reset();

-- da terminale:
--   docker compose exec db pgbench -U postgres -d corso -n -c 4 -T 20 -f /scripts/workload.sql

-- Tre classifiche (cambia solo l'ORDER BY): total_exec_time, mean_exec_time, calls
SELECT left(regexp_replace(query, '\s+', ' ', 'g'), 60) AS query,
       calls,
       round(total_exec_time::numeric, 0) AS totale_ms,
       round(mean_exec_time::numeric, 2)  AS medio_ms
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY total_exec_time DESC
LIMIT 5;
-- atteso (dopo gli indici di 3.1–3.3): il report con JOIN è primo per tempo totale e medio;
--         la ricerca per cliente è prima per chiamate; la query più frequente non è la più pesante

SELECT left(regexp_replace(query, '\s+', ' ', 'g'), 50) AS query, calls, shared_blks_read, temp_blks_written
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY shared_blks_read DESC
LIMIT 3;



-- =============================================================================
-- Slide 3.15 · Le estensioni
-- =============================================================================

SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE name IN ('pg_stat_statements', 'pg_trgm', 'pgcrypto', 'hstore', 'citext', 'pageinspect',
               'pg_buffercache', 'postgres_fdw', 'btree_gist', 'postgis')
ORDER BY name;                                                   -- postgis assente: è esterna

SELECT extname, extversion FROM pg_extension ORDER BY extname;

-- pg_trgm: LIKE '%testo%' indicizzabile con GIN
BEGIN;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX demo_trgm ON customers USING gin (name gin_trgm_ops);
EXPLAIN SELECT id FROM customers WHERE name LIKE '%mer 1234%';   -- Bitmap Index Scan
ROLLBACK;



-- =============================================================================
-- Slide 4.01 · Array
-- =============================================================================

SELECT id, tags, cardinality(tags) AS n_tag FROM orders WHERE id IN (5, 7, 1000) ORDER BY id;

SELECT array_length('{}'::text[], 1) AS array_length_vuoto,        -- NULL
       cardinality('{}'::text[])     AS cardinality_vuoto;         -- 0

SELECT count(*) FROM orders WHERE tags @> ARRAY['vip'];            -- contiene: 1000
SELECT count(*) FROM orders WHERE tags && ARRAY['gift', 'express'];-- almeno uno in comune: 143715
SELECT count(*) FROM orders WHERE 'vip' = ANY (tags);              -- 1000 (equivalente, ma non indicizzabile da GIN)

SELECT t AS tag, count(*) FROM orders, unnest(tags) AS t GROUP BY t ORDER BY t;
-- atteso: express 143715 · gift 142715 · promo 170571 · vip 1000

SELECT customer_id, array_agg(id ORDER BY id) AS ordini
FROM orders WHERE customer_id IN (1, 2, 3) GROUP BY customer_id ORDER BY customer_id;

SELECT ARRAY['a'] || 'b'::text AS append, array_append(ARRAY['a'], 'b') AS append2;

-- DA SOLA: con || il letterale va tipizzato
SELECT tags || 'x' FROM orders WHERE id = 1000;
-- errore: malformed array literal: "x"



-- =============================================================================
-- Slide 4.02 · UUID
-- =============================================================================

SELECT gen_random_uuid() AS v4;                                    -- casuale (PG 13+)

-- DA SOLA (solo PG 18; prima: errore "function uuidv7() does not exist")
SELECT uuidv7() AS v7;

CREATE TABLE demo.u1 (id uuid   PRIMARY KEY, v int);
CREATE TABLE demo.b1 (id bigint PRIMARY KEY, v int);

DO $$
DECLARE t0 timestamptz;
BEGIN
  t0 := clock_timestamp();
  INSERT INTO demo.u1 SELECT gen_random_uuid(), g FROM generate_series(1, 500000) g;
  RAISE NOTICE 'UUID casuale: % ms', round(extract(epoch FROM clock_timestamp() - t0) * 1000);

  t0 := clock_timestamp();
  INSERT INTO demo.b1 SELECT g, g FROM generate_series(1, 500000) g;
  RAISE NOTICE 'bigint: % ms', round(extract(epoch FROM clock_timestamp() - t0) * 1000);
END $$;
-- atteso: l'UUID casuale è circa 3 volte più lento

SELECT pg_size_pretty(pg_relation_size('demo.u1_pkey')) AS indice_uuid,
       pg_size_pretty(pg_relation_size('demo.b1_pkey')) AS indice_bigint;
-- atteso: circa 18–19 MB · 11 MB



-- =============================================================================
-- Slide 4.03 · hstore e altri tipi
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS hstore;
SELECT 'a=>1, b=>2'::hstore -> 'a' AS valore_a, 'a=>1'::hstore ? 'b' AS ha_b;     -- 1 · false

-- Range con vincolo di esclusione: niente prenotazioni sovrapposte
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE TABLE demo.booking (
  room   int,
  during tstzrange,
  EXCLUDE USING gist (room WITH =, during WITH &&)
);
INSERT INTO demo.booking VALUES (1, '[2026-10-20 09:00, 2026-10-20 11:00)');
INSERT INTO demo.booking VALUES (2, '[2026-10-20 10:00, 2026-10-20 12:00)');     -- altra stanza: ok

-- DA SOLA: stessa stanza, periodo sovrapposto
INSERT INTO demo.booking VALUES (1, '[2026-10-20 10:00, 2026-10-20 12:00)');
-- errore: conflicting key value violates exclusion constraint "booking_room_during_excl"

SELECT '192.168.1.5'::inet << '192.168.1.0/24'::cidr AS dentro_la_rete;         -- true



-- =============================================================================
-- Slide 4.04 · json contro jsonb; accesso ai campi
-- =============================================================================

SELECT '{"b": 1, "a": 2, "a": 3}'::json  AS come_json,            -- testo identico, duplicati compresi
       '{"b": 1, "a": 2, "a": 3}'::jsonb AS come_jsonb;            -- {"a": 3, "b": 1}: ordinato, vince l'ultima chiave

SELECT attrs,
       attrs -> 'channel'    AS freccia,       -- jsonb: "app" (con le virgolette)
       attrs ->> 'channel'   AS testo,         -- text: app
       attrs['channel']      AS subscript,     -- PG 14+
       attrs #>> '{channel}' AS percorso
FROM orders WHERE id = 1000;

SELECT attrs ->> 'channel' AS canale, count(*) FROM orders GROUP BY 1 ORDER BY 1;
-- atteso: app 333334 · store 333333 · web 333333

SELECT ('{"n": 43}'::jsonb ->> 'n')::int + 1 AS dopo_il_cast;       -- 44: per usarlo come numero serve il cast



-- =============================================================================
-- Slide 4.05 · Operatori JSONB e jsonpath
-- =============================================================================

SELECT count(*) FROM orders WHERE attrs @> '{"coupon":"SPRING"}';         -- contenimento: 100000
SELECT count(*) FROM orders WHERE attrs ? 'risk';                         -- esistenza: 200
SELECT count(*) FROM orders WHERE attrs ?| ARRAY['risk', 'coupon'];       -- almeno una chiave
SELECT count(*) FROM orders WHERE attrs ?& ARRAY['risk', 'coupon'];       -- tutte le chiavi: 200

-- Modifica: jsonb_set, ||, - (in transazione)
BEGIN;
UPDATE orders SET attrs = jsonb_set(attrs, '{channel}', '"api"') || '{"note":"x"}' WHERE id = 1 RETURNING attrs;
UPDATE orders SET attrs = attrs - 'note' WHERE id = 1 RETURNING attrs;
ROLLBACK;

-- Costruire JSON direttamente da SQL
SELECT jsonb_build_object('cliente', c.id, 'ordini', jsonb_agg(o.id ORDER BY o.id)) AS risposta
FROM customers c JOIN orders o ON o.customer_id = c.id
WHERE c.id = 1
GROUP BY c.id;

-- jsonpath
SELECT count(*) FROM orders WHERE attrs @@ '$.channel == "app"';          -- 333334
SELECT count(*) FROM orders WHERE attrs @? '$.coupon';                    -- 100000
SELECT jsonb_path_query(attrs, '$.channel') AS canale FROM orders WHERE id = 1000;

-- DA SOLA (solo PG 17+; prima: errore di sintassi)
SELECT JSON_VALUE(attrs, '$.channel') FROM orders WHERE id = 1000;



-- =============================================================================
-- Slide 4.06 · Quando usare JSONB
-- =============================================================================

EXPLAIN SELECT count(*) FROM orders WHERE attrs ->> 'channel' = 'app';
-- atteso: rows ≈ 5000 stimate · reali 333.334 (nessuna statistica sui campi interni)

BEGIN;
CREATE INDEX demo_channel ON orders ((attrs ->> 'channel'));
ANALYZE orders;
EXPLAIN SELECT count(*) FROM orders WHERE attrs ->> 'channel' = 'app';
-- atteso: rows ≈ 330.000 (333.767 nella prova; dipende dal campione di ANALYZE): l'indice su espressione porta con sé le statistiche
ROLLBACK;

-- Alternativa: colonna generata
CREATE TABLE demo.eventi (
  id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payload jsonb NOT NULL,
  tipo    text GENERATED ALWAYS AS (payload ->> 'tipo') STORED
);
INSERT INTO demo.eventi (payload) VALUES ('{"tipo": "login", "utente": 1}'), ('{"tipo": "logout"}');
SELECT id, tipo FROM demo.eventi;                                          -- login · logout



-- =============================================================================
-- Slide 4.07 · Trigger e PL/pgSQL
-- =============================================================================

CREATE TABLE demo.t_upd (id int PRIMARY KEY, val text, updated_at timestamptz DEFAULT now());

-- In DBeaver: seleziona tutto il blocco CREATE FUNCTION e usa "Esegui istruzione"
CREATE FUNCTION demo.set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_upd BEFORE UPDATE ON demo.t_upd
FOR EACH ROW EXECUTE FUNCTION demo.set_updated_at();

INSERT INTO demo.t_upd (id, val) VALUES (1, 'a');
SELECT updated_at FROM demo.t_upd WHERE id = 1;

SELECT pg_sleep(2);
UPDATE demo.t_upd SET val = 'b' WHERE id = 1 RETURNING updated_at;         -- avanzato di circa 2 s, senza che la query lo imposti

DO $$ BEGIN UPDATE demo.t_upd SET val = 'c' WHERE id = 1; END $$;          -- il trigger scatta anche da PL/pgSQL
SELECT val, updated_at FROM demo.t_upd WHERE id = 1;

SELECT pg_get_functiondef('demo.set_updated_at'::regproc);                  -- il codice della funzione



-- =============================================================================
-- Slide 4.08 · Oltre il B-Tree: GIN
-- =============================================================================

BEGIN;
EXPLAIN (ANALYZE, BUFFERS) SELECT id FROM orders WHERE tags @> ARRAY['vip'];       -- Seq Scan

CREATE INDEX demo_tags ON orders USING gin (tags);
EXPLAIN (ANALYZE, BUFFERS) SELECT id FROM orders WHERE tags @> ARRAY['vip'];       -- valore raro: Bitmap Index Scan, pochi ms
EXPLAIN (ANALYZE, BUFFERS) SELECT id FROM orders WHERE tags @> ARRAY['promo'];     -- 17%: usa il GIN ma legge quasi tutte le pagine
EXPLAIN SELECT id FROM orders WHERE 'vip' = ANY (tags);                            -- Seq Scan: = ANY non è un operatore GIN

CREATE INDEX demo_attrs_path ON orders USING gin (attrs jsonb_path_ops);
EXPLAIN SELECT id FROM orders WHERE attrs @> '{"risk":"high"}';                    -- usa demo_attrs_path
EXPLAIN SELECT id FROM orders WHERE attrs ? 'risk';                                -- Seq Scan: path_ops non supporta ?

CREATE INDEX demo_attrs ON orders USING gin (attrs);
EXPLAIN SELECT id FROM orders WHERE attrs ? 'risk';                                -- ora usa demo_attrs

SELECT pg_size_pretty(pg_relation_size('demo_tags'))       AS gin_tags,
       pg_size_pretty(pg_relation_size('demo_attrs_path')) AS path_ops,
       pg_size_pretty(pg_relation_size('demo_attrs'))      AS jsonb_ops;
-- atteso: circa 1,3 MB · 1,2 MB · 2,4 MB
ROLLBACK;



-- =============================================================================
-- Slide 4.09 · BRIN
-- =============================================================================

SELECT attname, round(correlation::numeric, 2) AS correlazione
FROM pg_stats
WHERE schemaname = 'public' AND tablename = 'orders' AND attname IN ('created_at', 'customer_id');
-- atteso: created_at circa 1 · customer_id circa 0: BRIN va bene solo sulla prima

BEGIN;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(total) FROM orders WHERE created_at >= '2026-03-01' AND created_at < '2026-03-02';
-- atteso: Seq Scan · 2880 righe

CREATE INDEX demo_brin ON orders USING brin (created_at);
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(total) FROM orders WHERE created_at >= '2026-03-01' AND created_at < '2026-03-02';
-- atteso: Bitmap Heap Scan con Heap Blocks lossy e Rows Removed by Index Recheck

CREATE INDEX demo_btree ON orders (created_at);
SELECT pg_size_pretty(pg_relation_size('demo_brin'))  AS brin,
       pg_size_pretty(pg_relation_size('demo_btree')) AS btree;
-- atteso: circa 24 kB · 21 MB
ROLLBACK;



-- =============================================================================
-- Slide 4.10 · Dead tuples, VACUUM e VACUUM FULL
-- =============================================================================

CREATE TABLE demo.vac (id int PRIMARY KEY, val text, pad text) WITH (autovacuum_enabled = false);
INSERT INTO demo.vac SELECT g, 'v' || g, repeat('x', 100) FROM generate_series(1, 200000) g;

SELECT pg_size_pretty(pg_relation_size('demo.vac')) AS heap, pg_size_pretty(pg_relation_size('demo.vac_pkey')) AS indice;
-- atteso: 28 MB · circa 4,3 MB

UPDATE demo.vac SET val = val || '!';
SELECT pg_size_pretty(pg_relation_size('demo.vac')) AS heap;      -- 56 MB: ogni riga ha due versioni

VACUUM demo.vac;
SELECT pg_size_pretty(pg_relation_size('demo.vac')) AS heap;      -- 56 MB: invariata, lo spazio è solo riutilizzabile

UPDATE demo.vac SET val = val || '?';
SELECT pg_size_pretty(pg_relation_size('demo.vac')) AS heap;      -- 57 MB: lo spazio liberato viene riusato

VACUUM FULL demo.vac;                                             -- riscrive la tabella (lock ACCESS EXCLUSIVE)
SELECT pg_size_pretty(pg_relation_size('demo.vac')) AS heap;      -- 28 MB



-- =============================================================================
-- Slide 4.11 · Transazioni lunghe: il nemico del VACUUM
-- =============================================================================

-- Due sessioni, A e B (tabella demo.vac della slide 4.10)
--   [A] BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT count(*) FROM demo.vac;    -- la transazione resta aperta
--   [B] UPDATE demo.vac SET val = val || '#';
--   [B] VACUUM (VERBOSE) demo.vac;
--       → console output: "200000 are dead but not yet removable"
--   [B] SELECT pid, state, now() - xact_start AS durata, backend_xmin
--       FROM pg_stat_activity WHERE backend_xmin IS NOT NULL ORDER BY age(backend_xmin) DESC;
--       → da B: A risulta "idle in transaction" (dalla stessa A la sua riga sarebbe "active")
--   [A] COMMIT;
--   [B] VACUUM (VERBOSE) demo.vac;                                               -- ora i dead tuples vengono rimossi
-- Prevenzione: transazioni brevi e
--   ALTER SYSTEM SET idle_in_transaction_session_timeout = '5min';  -- poi SELECT pg_reload_conf();



-- =============================================================================
-- Slide 4.12 · Autovacuum
-- =============================================================================

SELECT name, setting, unit FROM pg_settings
WHERE name IN ('autovacuum', 'autovacuum_naptime', 'autovacuum_vacuum_threshold', 'autovacuum_vacuum_scale_factor',
               'autovacuum_analyze_scale_factor', 'autovacuum_vacuum_insert_threshold')
ORDER BY name;

-- Soglia di default contro soglia per tabella (tabella nuova, così n_dead_tup parte pulito)
CREATE TABLE demo.av (id int PRIMARY KEY, val text) WITH (autovacuum_enabled = false);
INSERT INTO demo.av SELECT g, 'v' FROM generate_series(1, 200000) g;
ANALYZE demo.av;

ALTER TABLE demo.av SET (autovacuum_enabled = true, autovacuum_vacuum_scale_factor = 0.01, autovacuum_vacuum_threshold = 100);

SELECT reltuples::bigint AS righe,
       round(50  + 0.2  * reltuples) AS soglia_default,
       round(100 + 0.01 * reltuples) AS soglia_tabella
FROM pg_class WHERE oid = 'demo.av'::regclass;
-- atteso: 200000 righe · soglia default circa 40.050 · soglia per tabella circa 2.100

SELECT reloptions FROM pg_class WHERE oid = 'demo.av'::regclass;

-- Con 5000 righe aggiornate si supera la soglia: dopo qualche secondo scatta l'autovacuum
UPDATE demo.av SET val = 'w' WHERE id <= 5000;
SELECT pg_sleep(20);
SELECT last_autovacuum, autovacuum_count, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'av';
-- atteso: autovacuum_count = 1 e n_dead_tup = 0 con autovacuum_naptime = 10s (compose del corso);
-- se non è ancora scattato, ripetere la query: subito dopo il caricamento del dump l'autovacuum può essere
-- ancora occupato (e rallentato di proposito) sulle tabelle grandi; con il default di 1 minuto, attendere di più



-- =============================================================================
-- Slide 4.13 · HOT update e wraparound
-- =============================================================================

CREATE TABLE demo.h70  (id int PRIMARY KEY, val text) WITH (fillfactor = 70,  autovacuum_enabled = false);
CREATE TABLE demo.h100 (id int PRIMARY KEY, val text) WITH (fillfactor = 100, autovacuum_enabled = false);
INSERT INTO demo.h70  SELECT g, repeat('x', 50) FROM generate_series(1, 100000) g;
INSERT INTO demo.h100 SELECT g, repeat('x', 50) FROM generate_series(1, 100000) g;

UPDATE demo.h70  SET val = repeat('y', 50) WHERE id % 3 = 0;
UPDATE demo.h100 SET val = repeat('y', 50) WHERE id % 3 = 0;

SELECT pg_stat_force_next_flush();
SELECT relname, n_tup_upd, n_tup_hot_upd FROM pg_stat_user_tables WHERE relname IN ('h70', 'h100') ORDER BY relname;
-- atteso: h100 · 33333 · 0  /  h70 · 33333 · 33333

-- Wraparound: età degli identificativi di transazione
SELECT datname, age(datfrozenxid) AS eta FROM pg_database ORDER BY eta DESC;
SHOW autovacuum_freeze_max_age;                                   -- 200000000



-- =============================================================================
-- Pulizia · elimina lo schema demo
-- =============================================================================

RESET ALL;
DROP SCHEMA IF EXISTS demo CASCADE;
