DROP TABLE IF EXISTS order_items, orders, customers CASCADE;

CREATE TABLE customers (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email      text        NOT NULL UNIQUE,
  name       text        NOT NULL,
  country    text        NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE orders (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id bigint        NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
  status      text          NOT NULL DEFAULT 'pending'
              CHECK (status IN ('pending','paid','shipped','delivered','cancelled')),
  total       numeric(12,2) NOT NULL CHECK (total >= 0),
  created_at  timestamptz   NOT NULL DEFAULT now(),
  tags        text[]        NOT NULL DEFAULT '{}',   -- pomeriggio: array/GIN
  attrs       jsonb         NOT NULL DEFAULT '{}'    -- pomeriggio: JSONB/GIN
);

CREATE TABLE order_items (
  order_id   bigint        NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  line_no    int           NOT NULL,
  sku        text          NOT NULL,
  qty        int           NOT NULL CHECK (qty > 0),
  unit_price numeric(10,2) NOT NULL CHECK (unit_price >= 0),
  PRIMARY KEY (order_id, line_no)
);




TRUNCATE order_items, orders, customers RESTART IDENTITY;

-- Seme fisso: random() produce sempre gli stessi valori, quindi tutti i partecipanti hanno lo stesso dataset
-- (e i risultati attesi della dispensa di laboratorio coincidono). Vale per la stessa sessione: eseguire lo script per intero.
SELECT setseed(0.42);

INSERT INTO customers (email, name, country)
SELECT 'user' || g || '@example.com',
       'Customer ' || g,
       (ARRAY['IT','IT','IT','IT','FR','DE','ES','GB','US'])[1 + (g % 9)]
FROM generate_series(1, 100000) AS g;

INSERT INTO orders (customer_id, status, total, created_at, tags, attrs)
SELECT 1 + (random() * 99999)::int,
       CASE WHEN r < 0.900 THEN 'delivered'
            WHEN r < 0.960 THEN 'shipped'
            WHEN r < 0.990 THEN 'paid'
            WHEN r < 0.998 THEN 'cancelled'
            ELSE 'pending' END,
       round((random() * 500)::numeric + 5, 2),
       timestamptz '2026-01-01' + g * interval '30 seconds',
       CASE WHEN g % 1000 = 0 THEN ARRAY['vip','express']
            WHEN g % 7    = 0 THEN ARRAY['gift','express']
            WHEN g % 5    = 0 THEN ARRAY['promo']
            ELSE ARRAY[]::text[] END,
       jsonb_strip_nulls(jsonb_build_object(
         'channel', (ARRAY['web','app','store'])[1 + (g % 3)],
         'coupon',  CASE WHEN g % 10   = 0 THEN 'SPRING' END,
         'risk',    CASE WHEN g % 5000 = 0 THEN 'high'   END))
FROM (SELECT g, random() AS r FROM generate_series(1, 1000000) AS g) s;

INSERT INTO order_items (order_id, line_no, sku, qty, unit_price)
SELECT o.id, l,
       'SKU-' || (1 + (random() * 199)::int),
       1 + (random() * 4)::int,
       round((random() * 100)::numeric + 1, 2)
FROM orders o
CROSS JOIN LATERAL generate_series(1, 1 + (o.id % 3)::int) AS l;


-- ##########################################################################
-- VERIFICA FINALE
-- ##########################################################################
SELECT 'public.customers', count(*) FROM customers
UNION ALL SELECT 'public.orders', count(*) FROM orders
UNION ALL SELECT 'public.order_items', count(*) FROM order_items;
-- Atteso: customers 100000 · orders 1000000 · order_items ~2000000
