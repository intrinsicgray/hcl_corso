DROP SCHEMA IF EXISTS legacy CASCADE;
CREATE SCHEMA legacy;

CREATE TABLE legacy.ordini_flat (
  ordine_id     int,
  data_ordine   date,
  cliente_email text,
  cliente_nome  text,
  cliente_paese text,
  riga          int,
  sku           text,
  prodotto      text,
  prezzo        numeric(10,2),
  qta           int,
  stato         text
);

INSERT INTO legacy.ordini_flat
SELECT o,
       date '2025-01-01' + (o % 300),
       CASE WHEN o % 400 = 0 THEN NULL ELSE 'cliente' || c || '@shop.it' END,
       CASE WHEN o % 400 = 0 THEN NULL
            WHEN o % 53  = 0 THEN 'N. Cognome ' || c
            ELSE 'Nome Cognome ' || c END,
       CASE WHEN o % 400 = 0 THEN NULL
            WHEN o % 37  = 0 THEN lower((ARRAY['IT','IT','IT','FR','DE','ES'])[1 + c % 6])
            ELSE (ARRAY['IT','IT','IT','FR','DE','ES'])[1 + c % 6] END,
       r,
       'P' || lpad(p::text, 2, '0'),
       'Prodotto ' || lpad(p::text, 2, '0'),
       CASE WHEN date '2025-01-01' + (o % 300) >= date '2025-07-01' AND p % 5 = 0
            THEN round((5 + (p * 3) % 90) * 1.10, 2)
            ELSE (5 + (p * 3) % 90)::numeric END,
       1 + (o + r) % 3,
       CASE o % 10 WHEN 0 THEN 'annullato' WHEN 1 THEN 'in attesa' WHEN 2 THEN 'pagato' WHEN 3 THEN 'pagato'
                   WHEN 4 THEN 'spedito'   WHEN 5 THEN 'spedito'   ELSE 'consegnato' END
FROM generate_series(1, 2000) o
CROSS JOIN LATERAL (SELECT 1 + (o * 7) % 300 AS c) cc
CROSS JOIN LATERAL generate_series(1, 1 + o % 4) r
CROSS JOIN LATERAL (SELECT 1 + (o * 3 + r * 11) % 40 AS p) pp;

-- righe duplicate (errore tipico di un export): stessa riga di ordine presente due volte
INSERT INTO legacy.ordini_flat
SELECT * FROM legacy.ordini_flat WHERE ordine_id % 200 = 7 AND riga = 1;

SELECT count(*) AS righe,
       count(DISTINCT ordine_id) AS ordini,
       count(DISTINCT cliente_email) AS clienti,
       count(DISTINCT sku) AS prodotti
FROM legacy.ordini_flat;