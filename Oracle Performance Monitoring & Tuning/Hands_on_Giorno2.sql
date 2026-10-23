--1.Fase 1: La Baseline (Il problema di partenza):

SELECT /*+ GATHER_PLAN_STATISTICS LAB_DAY2_START */ c.nome, o.data_ordine, o.importo
FROM clienti c
JOIN ordini o ON c.cliente_id = o.cliente_id
WHERE c.cliente_id = 450 AND o.stato = 'IN_ATTESA';

--Estraiamo il piano 
SELECT sql_id, child_number, sql_text 
FROM v$sql 
WHERE sql_text LIKE '% LAB_DAY2_START %' 

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('3pgxuzzx4cbc3', NULL, 'ALLSTATS LAST'));

--Cosa evidenziare: Il piano mostrerà un HASH JOIN. Spiega che Oracle legge la riga del cliente 450, ma poi è costretto a fare un TABLE ACCESS FULL su tutti i 500.000 ordini per cercare le corrispondenze. 
--I Buffers (letture in RAM) saranno altissimi.

--2.Fase 2: La Creazione dell'Indice:Qualsiasi Client.
--creare alla classe l'indice mancante sulla chiave esterna (cliente_id nella tabella ordini).
CREATE INDEX idx_ordini_cliente ON ordini(cliente_id);
--Indicizzare le Foreign Key è la prima regola d'oro del design relazionale. Senza questo indice, ogni JOIN si trasforma in un Full Scan della tabella figlia.

--3.Fase 3: La Trasformazione (Nested Loop):Qualsiasi Client.
--rieseguire la stessa identica query, cambiando solo l'etichetta per evitare confusioni.

SELECT /*+ GATHER_PLAN_STATISTICS LAB_DAY2_FIX */ c.nome, o.data_ordine, o.importo
FROM clienti c
JOIN ordini o ON c.cliente_id = o.cliente_id
WHERE c.cliente_id = 450 AND o.stato = 'IN_ATTESA';

SELECT sql_id, child_number, sql_text 
FROM v$sql 
WHERE sql_text LIKE '% LAB_DAY2_FIX%' 

--estrarre il nuovo piano di esecuzione con DISPLAY_CURSOR.

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('4jd1s9f09xymc', NULL, 'ALLSTATS LAST'));

-- è apparso un MERGE JOIN CARTESIAN (Prodotto Cartesiano) invece di un Nested Loops, non hai sbagliato nulla: hai appena visto l'ottimizzatore di Oracle essere più intelligente di noi.
--Il "Mistero" del Merge Join Cartesian
--Di solito, un prodotto cartesiano è un disastro (avviene quando ci si dimentica la condizione di JOIN e il database moltiplica tutte le righe della tabella A per tutte le righe della tabella B). Ma qui la condizione di JOIN c'era!
--Perché lo ha fatto? Per un principio matematico chiamato Chiusura Transitiva (Transitive Closure).
--Ecco il ragionamento interno che ha fatto il Cost-Based Optimizer (CBO):
--1.	Tu hai scritto: c.cliente_id = o.cliente_id E c.cliente_id = 450.
--2.	Oracle ha dedotto matematicamente: "Se A = B e A = 450, allora anche B = 450".
--3.	Ha riscritto la tua query di nascosto in questo modo: WHERE c.cliente_id = 450 AND o.cliente_id = 450
--4.	A questo punto, ha interrogato la tabella clienti con la Primary Key e ha ottenuto esattamente 1 riga.
--5.	Ha interrogato la tabella ordini usando il tuo nuovo indice e ha estratto le righe.
--6.	Siccome i due set di dati sono stati filtrati in modo indipendente ed uno dei due è composto da una sola riga, 
--Oracle ha deciso che fare un vero "Nested Loop" (cercare le corrispondenze riga per riga) era uno spreco di tempo. 
--Ha semplicemente preso l'unica riga del cliente e l'ha "incollata" (prodotto cartesiano 1 x N) a tutte le righe degli ordini. Sforzo computazionale quasi zero!


SELECT /*+ GATHER_PLAN_STATISTICS LAB_DAY2_NESTED */ c.nome, o.data_ordine, o.importo
FROM clienti c
JOIN ordini o ON c.cliente_id = o.cliente_id
WHERE c.regione = 'Sud' AND o.stato = 'IN_ATTESA';

SELECT sql_id, child_number, sql_text 
FROM v$sql 
WHERE sql_text LIKE '% LAB_DAY2_NESTED%' ;

--estrarre il nuovo piano di esecuzione con DISPLAY_CURSOR.
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('5m7q2bdyd7931', NULL, 'ALLSTATS LAST'))


--Cosa succederà ora eseguendo questa query:
--1.	Oracle prenderà tutti i clienti della regione 'Sud' (saranno migliaia).
--2.	Per ogni singolo cliente trovato (ecco il "Loop"), userà il nuovo indice idx_ordini_cliente per andare a pescare istantaneamente i suoi ordini nella tabella figlia.
--3.	Nel piano di esecuzione apparirà finalmente l'operazione NESTED LOOPS supportata dall'INDEX RANGE SCAN.

--L'ottimizzatore ha scelto un HASH JOIN al posto del Nested Loops, ti sta dando una grandissima lezione su un concetto chiave del tuning: la Selettività.
--Quando abbiamo filtrato per regione = 'Sud', abbiamo chiesto a Oracle di elaborare circa il 25% dell'intera tabella clienti (2.500 clienti su 10.000).
--Il Cost-Based Optimizer (CBO) ha fatto questo calcolo: "Se uso il Nested Loop, devo prendere il primo cliente, saltare sull'indice degli ordini, pescare i dati dal disco...
--e ripetere questa operazione per 2.500 volte! Fare 2.500 salti casuali sul disco (Random I/O) 
--mi costa di più che leggere le due tabelle per intero in blocco (Sequential I/O) e incastrarle in memoria con un Hash."
--Il Nested Loop è la scelta migliore solo quando si estraggono poche righe (OLTP), mentre l'Hash Join vince sulle grandi moli di dati (Reportistica).

--Come mostrare il Nested Loops in aula (2 Metodi)
--Metodo 1: La via Naturale (Aumentare la Selettività)
--Invece di chiedere 2.500 clienti, chiediamone solo 10 (ad esempio usando un BETWEEN). 

SELECT /*+ GATHER_PLAN_STATISTICS LAB_DAY2_NL_NATURALE */ c.nome, o.data_ordine, o.importo
FROM clienti c
JOIN ordini o ON c.cliente_id = o.cliente_id
WHERE c.cliente_id BETWEEN 10 AND 20 
AND o.stato = 'IN_ATTESA';


SELECT sql_id, child_number, sql_text 
FROM v$sql 
WHERE sql_text LIKE '% LAB_DAY2_NL_NATURALE %' 


SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('fr32901pugrza', NULL, 'ALLSTATS LAST'));

--Metodo 2: La via di Forza (Uso degli Hint)
--Prendi la query originale (quella del 'Sud' che generava l'Hash Join) e inserisci un Hint per forzare Oracle a usare il Nested Loop contro la sua volontà.

SELECT /*+ GATHER_PLAN_STATISTICS USE_NL(c o) LAB_DAY2_NL_FORZATO */ c.nome, o.data_ordine, o.importo
FROM clienti c
JOIN ordini o ON c.cliente_id = o.cliente_id
WHERE c.regione = 'Sud' AND o.stato = 'IN_ATTESA';

--L'hint USE_NL(c o) impone il Nested Loop tra l'alias c e l'alias o.
SELECT sql_id, child_number, sql_text 
FROM v$sql 
WHERE sql_text LIKE '% LAB_DAY2_NL_FORZATO %' 



SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('2x36p9a3871pa', NULL, 'ALLSTATS LAST'));


--4.Fase 4: La Trappola (L'Indice Ignorato):
--Il tuning non è solo creare indici, ma anche capire come gli sviluppatori li "rompono". 
--creiamo un indice sulle date:

CREATE INDEX idx_ordini_data ON ordini(data_ordine);


SELECT /*+ GATHER_PLAN_STATISTICS LAB_DAY2_TRAP */ * 
FROM ordini 
WHERE TRUNC(data_ordine) = TO_DATE('2023-10-01', 'YYYY-MM-DD');

SELECT sql_id, child_number, sql_text 
FROM v$sql 
WHERE sql_text LIKE '% LAB_DAY2_TRAP %' 

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('6baxjpg72a1u9', NULL, 'ALLSTATS LAST'));

--Cosa succede: Il piano mostrerà un tremendo TABLE ACCESS FULL. L'indice viene ignorato!
--L'indice B-Tree contiene le date con ore, minuti e secondi. Applicando la funzione TRUNC() sulla colonna, 
--stiamo chiedendo a Oracle di trasformare ogni singolo dato prima di poterlo confrontare. Oracle è costretto a leggere l'intera tabella.

--5.Fase 5: La Soluzione alla Trappola (FBI):
--Come si risolve senza far riscrivere il codice all'applicazione? Con un Function-Based Index.

CREATE INDEX idx_ordini_data_func ON ordini(TRUNC(data_ordine));

--Rieseguendo la query della Fase 4, il piano tornerà ad essere un INDEX RANGE SCAN super ottimizzato.

SELECT /*+ GATHER_PLAN_STATISTICS LAB_DAY2_TRAP */ * 
FROM ordini 
WHERE TRUNC(data_ordine) = TO_DATE('2023-10-01', 'YYYY-MM-DD');

SELECT sql_id, child_number, sql_text 
FROM v$sql 
WHERE sql_text LIKE '% LAB_DAY2_TRAP %' 

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('dy8hwx8253gt9', NULL, 'ALLSTATS LAST'));
