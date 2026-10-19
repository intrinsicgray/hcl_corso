// ═══════════════════════════════════════════════════════════════════════════════
// Giorno 2 MongoDB · Script di demo per le slide (mattina e pomeriggio)
//
// Ogni blocco ha sopra un commento con il CODICE e il TITOLO della slide a cui si riferisce.
// I blocchi sono autonomi: preparano da soli i dati di cui hanno bisogno (collezioni `lab_*`) e si possono
// incollare uno alla volta nella shell di Compass, oppure eseguire tutto il file in una volta:
//
//     mongosh --quiet "mongodb://localhost:27017/?directConnection=true" < demo_slide_giorno2_mongodb.js
//
// Requisiti: database `shop` caricato dal servizio `seed` (100.000 clienti, 1.000.000 di ordini, `orders` senza
// indici secondari). Gli script NON modificano `orders` e `customers`, salvo dove indicato (e ripristinano).
// Il commento `// →` riporta l'esito atteso (quello mostrato nella slide, verificato su MongoDB 8.0.32).
// Alla fine del file c'è un blocco di PULIZIA che elimina collezioni, indici e view creati dalle demo.
//
// Errori ATTESI (fanno parte della demo, non sono guasti): [B1] `_id` immutabile · [U1] update senza operatori ·
//   [V1] `additionalProperties` senza `_id` · [V2] update in `strict` (121) · [IX4] parallel arrays, E11000 su `null`,
//   E11000 sull'indice unique su `customerId` · [AG5] memoria con `allowDiskUse: false`, `MaxTimeMSExpired`.
// Tempi: il file intero gira in circa 40 s su 1 vCPU; il TTL di [IX4] richiede 60-65 s di attesa (la find finale è commentata).
// Discrepanze trovate nelle slide (annotate nei blocchi): [AG4] contatori 5.000.000 e 50, non 5.000.005 e 55;
//   [A6] `_id: 900001` esiste già in `orders` (insert con E11000); [F0] `$budget` non è un campo del dataset.
// ═══════════════════════════════════════════════════════════════════════════════
// INDICE DEI BLOCCHI (codice e titolo della slide)
//   [O2] Ambiente, Compass e dataset
//   [B1] Database, collezioni, documenti, `_id` e ObjectId
//   [F0] Il linguaggio di query: MQL, non JavaScript
//   [B2] Tipi BSON e la trappola dei numeri
//   [B3] Importi e date: Decimal128 e Date
//   [B4] Documenti annidati, array, dot notation, 16 MB
//   [B5] Insert: creazione implicita, `insertMany`, `ordered`
//   [F1] Find: filtri, operatori e la regola dei negativi
//   [F1b] Carrellata di filtri e un esempio combinato
//   [F2] Campo assente e `null`; `$exists` e `$type`
//   [F3] Array e array di documenti: `$elemMatch`
//   [F4] Proiezione, ordinamento, paginazione
//   [U1] Operatori di update e atomicità del documento
//   [U2] Operatori sugli array
//   [U3] `upsert`, `findOneAndUpdate`, update con pipeline
//   [U4] `updateMany` non è atomico: update rieseguibili
//   [U5] Delete
//   [V1] Schema validation: `$jsonSchema`
//   [V2] Introdurre un validatore su dati esistenti
//   [A1] `mongod`, WiredTiger e cache
//   [A3] Replica set: primary, secondary, elezione
//   [A4] L'oplog
//   [A5] Demo: un `$inc` nell'oplog diventa il valore finale
//   [A6] Write concern e read concern
//   [A7] Read preference, configurazioni tipo e ritorno a CAP
//   [M5] N:N: array di riferimenti, doppio riferimento, collezione ponte
//   [M6] Extended reference: duplicazione controllata e riallineamento
//   [M8] Pattern: subset, computed, bucket, outlier
//   [TX2] Transazioni multi-documento: requisiti, isolamento, limiti
//   [TX3] Isolamento e `WriteConflict`
//   [IX1] Indici: `COLLSCAN`, `IXSCAN` e come leggere `explain`
//   [IX3] Indici composti e regola ESR
//   [IX4] Multikey, unique, partial, TTL
//   [IX5] Covered query, plan cache, costo degli indici
//   [AG1] Pipeline e stage: `find` vs `aggregate` e l'ordine logico SQL
//   [AG2] `$group`, `$project`/`$set`, `HAVING`
//   [AG3] `$unwind` e `$lookup`
//   [AG4] Demo: `hideIndex` e `$lookup`
//   [AG5] Ottimizzazione: `$match` in testa, memoria, `maxTimeMS`
//   [AG6] View: una pipeline con un nome
//   [AG7] View o `$merge`: ricalcolare o materializzare
// ═══════════════════════════════════════════════════════════════════════════════
use shop


// ───────────────────────────────────────────────────────────────────────────────
// [O2] Ambiente, Compass e dataset
// ───────────────────────────────────────────────────────────────────────────────
db.version()                                   // → '8.0.x'
rs.status().members[0].stateStr                // → 'PRIMARY'
db.customers.estimatedDocumentCount()          // → 100000
db.orders.estimatedDocumentCount()             // → 1000000
db.orders.findOne({ _id: 1 })                  // → il documento mostrato nella slide


// ───────────────────────────────────────────────────────────────────────────────
// [B1] Database, collezioni, documenti, `_id` e ObjectId
// ───────────────────────────────────────────────────────────────────────────────
db.getMongo().getDBNames().filter(n => ['admin', 'config', 'local'].includes(n))   // → [ 'admin', 'config', 'local' ]
db.getSiblingDB('local').getCollectionNames().includes('oplog.rs')                  // → true (l'oplog sta in `local`)
id = new ObjectId()                            // 12 byte: 4 di timestamp + 5 casuali per processo + 3 di contatore
id.getTimestamp()                              // → la data di creazione (secondi)
id.toString().length                           // → 24 (esadecimale)
db.lab_demo.drop()
db.lab_demo.insertOne({ _id: 'A', qty: 10 })   // la collezione nasce al primo insert
db.lab_demo.updateOne({ _id: 'A' }, { $set: { _id: 'B' } })    // → MongoServerError: ... the (immutable) field '_id'
db.lab_demo.drop()


// ───────────────────────────────────────────────────────────────────────────────
// [F0] Il linguaggio di query: MQL, non JavaScript
// ───────────────────────────────────────────────────────────────────────────────
// JavaScript: calcolato in mongosh (nella slide `const`; qui `var`, per poter ripetere il blocco)
var soglia = 100 * 1.22
// il server riceve { total: { $gt: 122 } }
db.orders.find({ total: { $gt: soglia } }).limit(2)
// MQL: confronto tra due campi (nella slide `$budget`; qui un campo che esiste: il totale supera la somma dei prezzi unitari?)
db.orders.find({ $expr: { $gt: ['$total', { $sum: '$items.unitPrice' }] } }).limit(2)
db.orders.countDocuments({ $expr: { $gt: ['$total', { $sum: '$items.unitPrice' }] } })


// ───────────────────────────────────────────────────────────────────────────────
// [B2] Tipi BSON e la trappola dei numeri
// ───────────────────────────────────────────────────────────────────────────────
db.lab_types.drop()
db.lab_types.insertMany([ { _id: 'int', v: 1 }, { _id: 'double', v: 1.5 }, { _id: 'big', v: 2147483648 },
                          { _id: 'long', v: NumberLong('1') }, { _id: 'string', v: '1' } ])
db.lab_types.aggregate([ { $project: { t: { $type: '$v' } } } ])
// → [ { _id: 'int', t: 'int' }, { _id: 'double', t: 'double' }, { _id: 'big', t: 'double' },
//     { _id: 'long', t: 'long' }, { _id: 'string', t: 'string' } ]


// ───────────────────────────────────────────────────────────────────────────────
// [B3] Importi e date: Decimal128 e Date
// ───────────────────────────────────────────────────────────────────────────────
db.lab_types.drop()
db.lab_types.insertMany([ { _id: 'money', a: NumberDecimal('0.1'), b: NumberDecimal('0.2') },
                          { _id: 'dateString', d: '2026-01-10' }, { _id: 'dateBson', d: ISODate('2026-01-10T00:00:00Z') } ])
// 0.30000000000000004
0.1 + 0.2
db.lab_types.aggregate([ { $match: { _id: 'money' } }, { $project: { sum: { $add: ['$a', '$b'] } } } ])
// con a = NumberDecimal('0.1') e b = NumberDecimal('0.2') → sum: Decimal128('0.3')
// trova la Date, non la stringa '2026-01-10'
db.lab_types.find({ d: { $gt: ISODate('2026-01-01T00:00:00Z') } })
// 'string': senza new, Date() restituisce una stringa
typeof Date()


// ───────────────────────────────────────────────────────────────────────────────
// [B4] Documenti annidati, array, dot notation, 16 MB
// ───────────────────────────────────────────────────────────────────────────────
// 333333
db.orders.countDocuments({ 'attrs.channel': 'web' })
// 300000: esclude gli ordini web con coupon o risk
db.orders.countDocuments({ attrs: { channel: 'web' } })
// 348
bsonsize(db.orders.findOne({ _id: 1 }))


// ───────────────────────────────────────────────────────────────────────────────
// [B5] Insert: creazione implicita, `insertMany`, `ordered`
// ───────────────────────────────────────────────────────────────────────────────
// un errore di battitura nel nome crea una collezione nuova, senza errori
db.lab_custmers.drop()
db.lab_custmers.insertOne({ name: 'Bianchi' })
db.getCollectionNames().filter(n => n.startsWith('lab_cust'))        // → [ 'lab_custmers' ]
db.lab_custmers.drop()
// duplicato in 2ª posizione
lotto = [ { _id: 'P-010', name: 'A' }, { _id: 'P-010', name: 'B' }, { _id: 'P-011', name: 'C' } ]
db.lab_demo.drop()
try { db.lab_demo.insertMany(lotto) } catch (e) { printjson({ inseriti: e.insertedCount, errori: e.writeErrors.map(w => ({ indice: w.index, codice: w.code })) }) }
db.lab_demo.countDocuments({})                                       // → 1   (ordered: true si ferma al primo errore)
db.lab_demo.drop()
try { db.lab_demo.insertMany(lotto, { ordered: false }) } catch (e) { printjson({ inseriti: e.insertedCount, errori: e.writeErrors.map(w => ({ indice: w.index, codice: w.code })) }) }
db.lab_demo.countDocuments({})                                       // → 2   (ordered: false scrive il 1° e il 3°)
db.lab_demo.drop()


// ───────────────────────────────────────────────────────────────────────────────
// [F1] Find: filtri, operatori e la regola dei negativi
// ───────────────────────────────────────────────────────────────────────────────
// è solo { tags: 'promo' }: la seconda chiave sovrascrive la prima (l'errore nasce in JavaScript, prima del server)
({ tags: 'gift', tags: 'promo' })
JSON.stringify({ tags: 'gift', tags: 'promo' })         // → '{"tags":"promo"}'
db.orders.countDocuments({ tags: 'promo' })                          // → 170571
db.orders.countDocuments({ tags: { $all: ['gift', 'promo'] } })      // → 0 (la query giusta per "entrambi")
// 999800: includono gli ordini senza risk
db.orders.countDocuments({ 'attrs.risk': { $nin: ['high'] } })
// 0
db.orders.countDocuments({ 'attrs.risk': { $exists: true, $ne: 'high' } })


// ───────────────────────────────────────────────────────────────────────────────
// [F1b] Carrellata di filtri e un esempio combinato
// ───────────────────────────────────────────────────────────────────────────────
db.orders.countDocuments({ status: 'delivered' })
db.orders.countDocuments({ total: { $gte: NumberDecimal('500') } })
db.orders.countDocuments({ status: { $in: ['paid', 'shipped'] } })
db.orders.countDocuments({ createdAt: { $gte: ISODate('2026-03-01'), $lt: ISODate('2026-04-01') } })
db.orders.countDocuments({ 'customer.country': 'IT' })
db.orders.countDocuments({ $or: [{ 'attrs.channel': 'app' }, { tags: 'gift' }] })
// esempio combinato: le condizioni si sommano nello stesso documento (AND implicito)
db.orders.find({
  // stato
  status: { $in: ['paid', 'shipped'] },
  // importo
  total: { $gte: NumberDecimal('500') },
  // intervallo semiaperto
  createdAt: { $gte: ISODate('2026-03-01'), $lt: ISODate('2026-04-01') },
  // campo annidato
  'customer.country': 'IT',
  // alternativa
  $or: [ { 'attrs.channel': 'app' }, { tags: 'gift' } ]
}, { total: 1, status: 1, 'customer.country': 1 }).limit(3)


// ───────────────────────────────────────────────────────────────────────────────
// [F2] Campo assente e `null`; `$exists` e `$type`
// ───────────────────────────────────────────────────────────────────────────────
db.lab_coupon.drop()
db.lab_coupon.insertMany([ { _id: 1, coupon: 'SPRING' }, { _id: 2, coupon: null }, { _id: 3 } ])
db.lab_coupon.find({ coupon: null }, { _id: 1 })                   // → 2 e 3  (null OPPURE assente)
db.lab_coupon.find({ coupon: { $exists: false } }, { _id: 1 })     // → solo 3 (assente)
db.lab_coupon.find({ coupon: { $type: 'null' } }, { _id: 1 })      // → solo 2 (vale null)
db.lab_coupon.find({ coupon: { $exists: true } }, { _id: 1 })      // → 1 e 2  (presente, anche se null)
// $type e il confronto numerico: 'number' = qualunque tipo numerico
db.lab_types.drop()
db.lab_types.insertMany([ { _id: 'int', v: 1 }, { _id: 'double', v: 1.5 }, { _id: 'long', v: NumberLong('1') }, { _id: 'string', v: '1' } ])
db.lab_types.find({ v: { $type: 'number' } }, { _id: 1 })          // → int, double, long
db.lab_types.find({ v: 1 }, { _id: 1 })                            // → int e long: il confronto numerico ignora il tipo
db.lab_coupon.drop()


// ───────────────────────────────────────────────────────────────────────────────
// [F3] Array e array di documenti: `$elemMatch`
// ───────────────────────────────────────────────────────────────────────────────
db.lab_orders.drop()
db.lab_orders.insertMany([ { _id: 1, items: [ { sku: 'A', qty: 1 }, { sku: 'B', qty: 5 } ] }, { _id: 2, items: [ { sku: 'A', qty: 5 } ] },
                           { _id: 3, items: [ { sku: 'B', qty: 2 } ], tags: ['gift'] }, { _id: 4, items: [], tags: ['gift', 'express'] } ])
// ordini con una riga di A in quantità >= 5: l'ordine 1 ha A×1 e B×5
// → 1 e 2
db.lab_orders.find({ 'items.sku': 'A', 'items.qty': { $gte: 5 } }, { _id: 1 })
// → solo 2
db.lab_orders.find({ items: { $elemMatch: { sku: 'A', qty: { $gte: 5 } } } }, { _id: 1 })
// i filtri della tabella, sul dataset
db.orders.countDocuments({ tags: 'gift' })                          // → 142715  (almeno un elemento)
db.orders.countDocuments({ tags: ['gift', 'express'] })             // → 142715  (array esatto)
db.orders.countDocuments({ tags: ['express', 'gift'] })             // → 0       (stesso insieme, altro ordine)
db.orders.countDocuments({ tags: { $all: ['express', 'gift'] } })   // → 142715  (in qualunque ordine)
db.orders.countDocuments({ tags: { $size: 0 } })                    // → 685714
db.orders.countDocuments({ 'tags.1': { $exists: true } })           // → 143715  ("almeno 2 elementi")


// ───────────────────────────────────────────────────────────────────────────────
// [F4] Proiezione, ordinamento, paginazione
// ───────────────────────────────────────────────────────────────────────────────
// inclusiva: solo nome e totale
db.orders.find({ status: 'delivered' }, { _id: 0, 'customer.name': 1, total: 1 }).limit(2)
// esclusiva: tutto tranne righe e attrs
db.orders.find({}, { items: 0, attrs: 0 }).limit(1)
// i 5 ordini più cari; _id rende l'ordine univoco
db.orders.find().sort({ total: -1, _id: 1 }).limit(5)
// pagina successiva, dopo l'ultimo _id visto
lastId = 900000
db.orders.find({ _id: { $gt: lastId } }).sort({ _id: 1 }).limit(20).toArray().map(d => d._id)     // (slide: senza .toArray().map per compattare l'output)
// skip contro range: totalKeysExamined
db.orders.find().sort({ _id: 1 }).skip(900000).limit(1).explain('executionStats').executionStats.totalKeysExamined                  // → 900001
db.orders.find({ _id: { $gt: 900000 } }).sort({ _id: 1 }).limit(1).explain('executionStats').executionStats.totalKeysExamined      // → 1


// ───────────────────────────────────────────────────────────────────────────────
// [U1] Operatori di update e atomicità del documento
// ───────────────────────────────────────────────────────────────────────────────
db.lab_products.drop()
db.lab_products.insertOne({ _id: 'P-001', name: 'Monitor 27"', price: NumberDecimal('249.90'), stock: NumberInt(12) })
// toglie 2 pezzi solo se ce ne sono almeno 2: un'unica operazione
db.lab_products.updateOne({ _id: 'P-001', stock: { $gte: 2 } }, { $inc: { stock: -2 } })           // → matchedCount: 1, modifiedCount: 1
// se non c'è abbastanza stock: matchedCount: 0, nessuna modifica
db.lab_products.updateOne({ _id: 'P-001', stock: { $gte: 20 } }, { $inc: { stock: -20 } })         // → matchedCount: 0, modifiedCount: 0
// un update senza operatori è rifiutato (per sostituire un documento: replaceOne)
db.lab_products.updateOne({ _id: 'P-001' }, { stock: 5 })       // → Update document requires atomic operators
// matchedCount vs modifiedCount: se il valore è già quello, nessuna scrittura
db.lab_products.updateOne({ _id: 'P-001' }, { $set: { stock: 10 } })                                // → matchedCount: 1, modifiedCount: 0


// ───────────────────────────────────────────────────────────────────────────────
// [U2] Operatori sugli array
// ───────────────────────────────────────────────────────────────────────────────
db.lab_products.drop()
db.lab_products.insertOne({ _id: 'P-001', name: 'Monitor 27"', tags: ['monitor', 'ufficio'] })
db.lab_orders.drop()
db.lab_orders.insertMany([ { _id: 'O-1', items: [ { sku: 'P-001', qty: 1 }, { sku: 'P-002', qty: 5 } ] }, { _id: 'O-2', items: [ { sku: 'P-001', qty: 2 } ] },
                           { _id: 'O-3', items: [ { sku: 'P-003', qty: 1 }, { sku: 'P-004', qty: 1 }, { sku: 'P-005', qty: 4 } ] }, { _id: 'O-4', items: [] } ])
// ultime 3 recensioni, la più recente in testa (array limitato)
db.lab_products.updateOne({ _id: 'P-001' },
  { $push: { lastReviews: { $each: [ { stars: 5, createdAt: new Date() } ], $position: 0, $slice: 3 } } })
// ripetuta con altre stelle: l'array non supera mai 3 elementi
;[4, 3, 2, 1].forEach(s => db.lab_products.updateOne({ _id: 'P-001' }, { $push: { lastReviews: { $each: [ { stars: s, createdAt: new Date() } ], $position: 0, $slice: 3 } } }))
db.lab_products.findOne({ _id: 'P-001' }).lastReviews.map(r => r.stars)            // → [ 1, 2, 3 ]
// segna tutte le righe con qty >= 4
db.lab_orders.updateMany({}, { $set: { 'items.$[r].flag': 'bulk' } }, { arrayFilters: [ { 'r.qty': { $gte: 4 } } ] })   // → matchedCount: 4, modifiedCount: 2
// $push con un array come argomento: aggiunge UN elemento che è un array (serve $each)
db.lab_products.updateOne({ _id: 'P-001' }, { $push: { tags: ['x', 'y'] } })
db.lab_products.findOne({ _id: 'P-001' }).tags                                     // → [ 'monitor', 'ufficio', [ 'x', 'y' ] ]
// $addToSet è idempotente
db.lab_products.updateOne({ _id: 'P-001' }, { $addToSet: { tags: 'promo' } })      // → modifiedCount: 1
db.lab_products.updateOne({ _id: 'P-001' }, { $addToSet: { tags: 'promo' } })      // → modifiedCount: 0


// ───────────────────────────────────────────────────────────────────────────────
// [U3] `upsert`, `findOneAndUpdate`, update con pipeline
// ───────────────────────────────────────────────────────────────────────────────
db.lab_counters.drop()
db.lab_orders.drop()
db.lab_orders.insertMany([ { _id: 'O-1', items: [ { sku: 'P-001', qty: 1 }, { sku: 'P-002', qty: 5 } ] }, { _id: 'O-2', items: [ { sku: 'P-001', qty: 2 } ] },
                           { _id: 'O-3', items: [ { sku: 'P-003', qty: 1 }, { sku: 'P-004', qty: 1 }, { sku: 'P-005', qty: 4 } ] }, { _id: 'O-4', items: [] } ])
// { _id: 'order', seq: 1 }
db.lab_counters.findOneAndUpdate({ _id: 'order' }, { $inc: { seq: 1 } }, { upsert: true, returnDocument: 'after' })
db.lab_counters.findOneAndUpdate({ _id: 'order' }, { $inc: { seq: 1 } }, { upsert: true, returnDocument: 'after' })    // → seq: 2
db.lab_orders.updateMany({}, [ { $set: { totalQty: { $sum: '$items.qty' } } } ])
db.lab_orders.find({}, { totalQty: 1 }).sort({ _id: 1 })                           // → O-1: 6, O-2: 2, O-3: 6, O-4: 0
// upsert con $setOnInsert: la seconda volta il documento c'è già e $setOnInsert è ignorato
db.lab_products.updateOne({ _id: 'P-007' }, { $set: { stock: 3 }, $setOnInsert: { price: NumberDecimal('12.00') } }, { upsert: true })   // → upsertedCount: 1
db.lab_products.updateOne({ _id: 'P-007' }, { $set: { stock: 3 }, $setOnInsert: { price: NumberDecimal('12.00') } }, { upsert: true })   // → matchedCount: 1, modifiedCount: 0


// ───────────────────────────────────────────────────────────────────────────────
// [U4] `updateMany` non è atomico: update rieseguibili
// ───────────────────────────────────────────────────────────────────────────────
db.lab_orders.drop()
db.lab_orders.insertMany([ { _id: 'O-1', items: [ { sku: 'P-001', qty: 1 }, { sku: 'P-002', qty: 5 } ] }, { _id: 'O-2', items: [ { sku: 'P-001', qty: 2 } ] },
                           { _id: 'O-3', items: [ { sku: 'P-003', qty: 1 }, { sku: 'P-004', qty: 1 }, { sku: 'P-005', qty: 4 } ] }, { _id: 'O-4', items: [] } ])
oplog = db.getSiblingDB('local').oplog.rs
t0 = oplog.find().sort({ $natural: -1 }).limit(1).next().ts           // dove siamo nell'oplog
// rieseguibile: il filtro esclude i documenti già fatti, il valore si imposta con $set (non $inc)
db.lab_orders.updateMany({ totalQty: { $exists: false } }, [ { $set: { totalQty: { $sum: '$items.qty' } } } ])   // → modifiedCount: 4
// quattro documenti = quattro voci nell'oplog: non una operazione sola
oplog.countDocuments({ ns: 'shop.lab_orders', op: 'u', ts: { $gt: t0 } })       // → 4
db.lab_orders.updateMany({ totalQty: { $exists: false } }, [ { $set: { totalQty: { $sum: '$items.qty' } } } ])   // → modifiedCount: 0 (rieseguibile)


// ───────────────────────────────────────────────────────────────────────────────
// [U5] Delete
// ───────────────────────────────────────────────────────────────────────────────
db.lab_del.drop()
db.createCollection('lab_del', { validator: { $jsonSchema: { bsonType: 'object', required: ['x'] } } })
db.lab_del.createIndex({ x: 1 })
db.lab_del.insertMany([ { x: 1 }, { x: 2 }, { x: 3 } ])
// il caso reale: un filtro costruito da parametri facoltativi che, se nessuno è valorizzato, diventa {}
clienteId = null
filtro = {}
if (clienteId) filtro.customerId = clienteId
filtro                                                                        // → {}   (cancellerebbe TUTTO)
db.lab_del.countDocuments(filtro)                                             // → 3    (il conteggio con lo stesso filtro, PRIMA di cancellare)
db.lab_del.deleteMany({})                                                     // → deletedCount: 3
db.lab_del.getIndexes().length                                                // → 2   (indici: restano)
db.getCollectionInfos({ name: 'lab_del' })[0].options.validator !== undefined // → true (il validatore resta)
db.lab_del.drop()                                                             // collezione, indici e validatore eliminati
db.getCollectionNames().includes('lab_del')                                   // → false


// ───────────────────────────────────────────────────────────────────────────────
// [V1] Schema validation: `$jsonSchema`
// ───────────────────────────────────────────────────────────────────────────────
db.lab_products.drop()
db.lab_products.insertOne({ _id: 'P-001', name: 'Monitor 27"', price: NumberDecimal('249.90'), stock: NumberInt(12) })
db.runCommand({ collMod: 'lab_products',
  validator: { $jsonSchema: { bsonType: 'object', required: ['name', 'price'],
    properties: { name:  { bsonType: 'string', minLength: 1 },
                  price: { bsonType: 'decimal', minimum: 0 },
                  stock: { bsonType: 'int', minimum: 0 },
                  tags:  { bsonType: 'array', items: { bsonType: 'string' } } } } },
  validationLevel: 'moderate', validationAction: 'error' })
// un prezzo scritto come numero semplice è un int: rifiutato (codice 121), errInfo dice quale regola e quale campo
try { db.lab_products.insertOne({ _id: 'P-099', name: 'Prova', price: 10 }) } catch (e) { print(e.code); printjson(e.errInfo.details.schemaRulesNotSatisfied) }
db.lab_products.insertOne({ _id: 'P-099', name: 'Prova', price: NumberDecimal('10.00') })     // → accettato
// additionalProperties: false: va elencato anche _id
db.lab_strict.drop()
db.createCollection('lab_strict', { validator: { $jsonSchema: { bsonType: 'object', properties: { name: { bsonType: 'string' } }, additionalProperties: false } } })
db.lab_strict.insertOne({ name: 'x' })                                         // → Document failed validation (manca _id nelle properties)
db.runCommand({ collMod: 'lab_strict', validator: { $jsonSchema: { bsonType: 'object', properties: { _id: {}, name: { bsonType: 'string' } }, additionalProperties: false } } })
db.lab_strict.insertOne({ name: 'x' })                                         // → accettato
db.lab_strict.drop()


// ───────────────────────────────────────────────────────────────────────────────
// [V2] Introdurre un validatore su dati esistenti
// ───────────────────────────────────────────────────────────────────────────────
db.lab_products.drop()
db.lab_products.insertMany([ { _id: 'P-001', name: 'Monitor 27"', price: NumberDecimal('249.90') },
                             { _id: 'P-006', name: 'Cavo HDMI', price: 9.9, stock: NumberLong(100) } ])   // P-006: dato "sporco" (price double)
schema = { $jsonSchema: { bsonType: 'object', required: ['name', 'price'],
  properties: { name: { bsonType: 'string', minLength: 1 }, price: { bsonType: 'decimal', minimum: 0 } } } }
db.runCommand({ collMod: 'lab_products', validator: schema, validationLevel: 'strict', validationAction: 'error' })   // non controlla i dati esistenti
db.lab_products.find({ $nor: [ schema ] }, { _id: 1 })                         // → P-006
// strict: un update di un documento già non valido è controllato, anche se non c'entra con il campo sbagliato
db.lab_products.updateOne({ _id: 'P-006' }, { $set: { tags: ['video'] } })     // → Document failed validation (121)
// moderate: l'update di un documento già non valido NON è controllato
db.runCommand({ collMod: 'lab_products', validationLevel: 'moderate' })
db.lab_products.updateOne({ _id: 'P-006' }, { $set: { tags: ['video'] } })     // → modifiedCount: 1
// si corregge, poi si irrigidisce
db.lab_products.updateOne({ _id: 'P-006' }, { $set: { price: NumberDecimal('9.90'), stock: NumberInt(100) } })
db.lab_products.countDocuments({ $nor: [ schema ] })                           // → 0
db.runCommand({ collMod: 'lab_products', validationLevel: 'strict' })
// warn: accetta e scrive la violazione nel log (id 20294)
db.runCommand({ collMod: 'lab_products', validationAction: 'warn' })
db.lab_products.insertOne({ _id: 'P-100', name: 'Senza prezzo' })              // → accettato
db.adminCommand({ getLog: 'global' }).log.filter(r => r.includes('Document would fail validation')).slice(-1).map(r => JSON.parse(r).id)   // → [ 20294 ]


// ───────────────────────────────────────────────────────────────────────────────
// [A1] `mongod`, WiredTiger e cache
// ───────────────────────────────────────────────────────────────────────────────
c = db.serverStatus().wiredTiger.cache
({ maxMB: Math.round(c['maximum bytes configured'] / 1048576), usedMB: Math.round(c['bytes currently in the cache'] / 1048576), dirtyMB: Math.round(c['tracked dirty bytes in the cache'] / 1048576) })
s = db.orders.stats({ scale: 1048576 })
({ datiMB: Math.round(s.size), discoMB: Math.round(s.storageSize), indiciMB: Math.round(s.totalIndexSize), rapporto: +(s.size / s.storageSize).toFixed(1) })   // → circa 339 / 89–93 / 28 / 3,7–3,8
db.serverStatus().connections                                                   // un thread per connessione


// ───────────────────────────────────────────────────────────────────────────────
// [A3] Replica set: primary, secondary, elezione
// ───────────────────────────────────────────────────────────────────────────────
st = rs.status()
({ set: st.set, myState: st.myState, members: st.members.map(m => ({ name: m.name, stateStr: m.stateStr, health: m.health })) })   // → un solo membro: PRIMARY
rs.conf().members.map(m => ({ host: m.host, priority: m.priority, votes: m.votes }))        // → host 'localhost:27017' (visto dal container)
rs.conf().settings.electionTimeoutMillis                                                    // → 10000 (10 s)
db.hello().isWritablePrimary                                                                // → true


// ───────────────────────────────────────────────────────────────────────────────
// [A4] L'oplog
// ───────────────────────────────────────────────────────────────────────────────
db.lab_orders.drop()
db.lab_orders.insertOne({ _id: 'O-5', status: 'paid', items: [] })
db.getSiblingDB('local').oplog.rs.find({ ns: 'shop.lab_orders' }, { op: 1, ns: 1, o: 1, _id: 0 }).sort({ $natural: -1 }).limit(1)
// dimensione e finestra dell'oplog
rs.printReplicationInfo()


// ───────────────────────────────────────────────────────────────────────────────
// [A5] Demo: un `$inc` nell'oplog diventa il valore finale
// ───────────────────────────────────────────────────────────────────────────────
db.lab_demo.drop()
db.lab_demo.insertOne({ _id: 'A', qty: 10 })
db.lab_demo.updateOne({ _id: 'A' }, { $inc: { qty: 1 } })
db.getSiblingDB('local').oplog.rs.find({ ns: 'shop.lab_demo', op: 'u' }, { o: 1, o2: 1, _id: 0 }).sort({ $natural: -1 }).limit(1)
// → [ { o: { '$v': 2, diff: { u: { qty: 11 } } }, o2: { _id: 'A' } } ]
db.lab_demo.drop()


// ───────────────────────────────────────────────────────────────────────────────
// [A6] Write concern e read concern
// NOTA: la slide inserisce `_id: 900001` in `orders`, ma quell'`_id` esiste già (il dataset va da 1 a 1.000.000):
//       l'insert darebbe E11000. Qui si usa `lab_orders` con un `_id` nuovo; la scrittura su `orders` resterebbe in ogni caso.
// ───────────────────────────────────────────────────────────────────────────────
db.lab_orders.drop()
db.lab_orders.insertOne(
  { _id: 'O-900', status: 'paid', total: NumberDecimal('129.90') },
  // attende maggioranza + journal, max 5 s
  { writeConcern: { w: 'majority', j: true, wtimeout: 5000 } }
)
// solo dati non annullabili
db.lab_orders.find({ status: 'paid' }).readConcern('majority')
// nodo singolo: errore 100, ma l'update resta
try { db.lab_orders.updateOne({ _id: 'O-900' }, { $set: { status: 'shipped' } }, { writeConcern: { w: 2 } }) } catch (e) { print(e.code, e.codeName) }   // → 100 UnsatisfiableWriteConcern
db.lab_orders.findOne({ _id: 'O-900' }).status                                  // → 'shipped'  (la scrittura è rimasta)
db.adminCommand({ getDefaultRWConcern: 1 })                                     // default: write concern majority (implicito), read concern local


// ───────────────────────────────────────────────────────────────────────────────
// [A7] Read preference, configurazioni tipo e ritorno a CAP
// ───────────────────────────────────────────────────────────────────────────────
db.getMongo().getReadPrefMode()                                                 // → 'primary' (default)
db.orders.find().readPref('secondaryPreferred').limit(1).toArray().length       // → 1  (nodo singolo: ripiega sul primary)
db.orders.find({ status: 'paid' }).readPref('nearest').readConcern('local').limit(1).toArray().length   // → 1


// ═══════════════════════════════════════════════════════════════════════════════
// POMERIGGIO
// ═══════════════════════════════════════════════════════════════════════════════


// ───────────────────────────────────────────────────────────────────────────────
// [M5] N:N: array di riferimenti, doppio riferimento, collezione ponte
// ───────────────────────────────────────────────────────────────────────────────
db.lab_courses.drop(); db.lab_students.drop(); db.lab_enrollments.drop()
db.lab_courses.insertMany([ { _id: 'c1', title: 'PostgreSQL' }, { _id: 'c2', title: 'MongoDB' }, { _id: 'c3', title: 'Kafka' } ])
db.lab_students.insertMany([ { _id: 's1', name: 'Anna', courseIds: ['c1', 'c2'] }, { _id: 's2', name: 'Luca', courseIds: ['c2'] }, { _id: 's3', name: 'Sara', courseIds: ['c2', 'c3'] } ])
// modello "un lato": l'array courseIds sta solo negli studenti
db.lab_students.createIndex({ courseIds: 1 })
db.lab_students.find({ courseIds: 'c2' }, { name: 1 })        // studenti del corso c2  → s1, s2, s3
// i corsi di uno studente: $lookup su un array di riferimenti
db.lab_students.aggregate([ { $match: { _id: 's1' } },
  { $lookup: { from: 'lab_courses', localField: 'courseIds', foreignField: '_id', as: 'courses' } }, { $project: { name: 1, 'courses.title': 1 } } ])
// collezione ponte: il legame ha attributi propri
db.lab_enrollments.insertOne({ studentId: 's1', courseId: 'c2', enrolledAt: new Date(), grade: 28 })
db.lab_enrollments.find({ courseId: 'c2' })


// ───────────────────────────────────────────────────────────────────────────────
// [M6] Extended reference: duplicazione controllata e riallineamento
// (modifica 10 ordini del cliente 4242 e li ripristina al termine)
// ───────────────────────────────────────────────────────────────────────────────
db.orders.findOne({ _id: 4242 })                                  // riferimento (customerId) + copia (customer)
db.orders.countDocuments({ customerId: 4242 })                    // → 10
db.customers.updateOne({ _id: 4242 }, { $set: { name: 'Mario Rossi' } })
// riallineamento: rieseguibile (il filtro esclude gli ordini già corretti)
db.orders.updateMany({ customerId: 4242, 'customer.name': { $ne: 'Mario Rossi' } }, { $set: { 'customer.name': 'Mario Rossi' } })   // → matchedCount: 10, modifiedCount: 10
// il costo: 10 ordini toccati, ma senza indice su customerId il server ne esamina un milione
db.orders.find({ customerId: 4242 }).explain('executionStats').executionStats.totalDocsExamined         // → 1000000
// ripristino
db.customers.updateOne({ _id: 4242 }, { $set: { name: 'Customer 4242' } })
db.orders.updateMany({ customerId: 4242 }, { $set: { 'customer.name': 'Customer 4242' } })


// ───────────────────────────────────────────────────────────────────────────────
// [M8] Pattern: subset, computed, bucket, outlier
// ───────────────────────────────────────────────────────────────────────────────
db.lab_products.drop()
db.lab_products.insertOne({ _id: 'P-001', name: 'Monitor 27"', rating: { count: 12, sum: 35 }, lastReviews: [] })
// nuova recensione: subset + computed in un'unica operazione atomica sul prodotto
db.lab_products.updateOne({ _id: 'P-001' }, {
  $inc:  { 'rating.count': 1, 'rating.sum': 5 },
  $push: { lastReviews: { $each: [ { stars: 5, customerId: 7, createdAt: new Date() } ], $position: 0, $slice: 5 } } })
db.lab_products.findOne({ _id: 'P-001' })                         // → rating { count: 13, sum: 40 }, una recensione in lastReviews
// il voto medio si ricava in lettura: count e sum, non la media
db.lab_products.aggregate([ { $project: { media: { $round: [ { $divide: ['$rating.sum', '$rating.count'] }, 2 ] } } } ])   // → 3.08


// ───────────────────────────────────────────────────────────────────────────────
// [TX2] Transazioni multi-documento: requisiti, isolamento, limiti
// (nella slide `const`; qui `var`, per poter incollare il blocco più volte)
// ───────────────────────────────────────────────────────────────────────────────
db.lab_accounts.drop()
db.lab_accounts.insertMany([ { _id: 'A', balance: NumberDecimal('100.00') }, { _id: 'B', balance: NumberDecimal('50.00') } ])
var s = db.getMongo().startSession()
var acc = s.getDatabase('shop').lab_accounts
s.startTransaction()
acc.updateOne({ _id: 'A' }, { $inc: { balance: NumberDecimal('-10.00') } })
acc.updateOne({ _id: 'B' }, { $inc: { balance: NumberDecimal('10.00') } })
s.commitTransaction()
s.endSession()
db.lab_accounts.find().sort({ _id: 1 })                           // → A 90.00, B 60.00 (visibili agli altri solo dopo il commit)
db.adminCommand({ getParameter: 1, transactionLifetimeLimitSeconds: 1, maxTransactionLockRequestTimeoutMillis: 1 })   // → 60 s, 5 ms


// ───────────────────────────────────────────────────────────────────────────────
// [TX3] Isolamento e `WriteConflict`
// DUE terminali (A e B) con la stessa connessione. Incolla tutto il blocco in entrambi, poi esegui i passi nell'ordine:
//   1 A  tx3_passo1()   2 B  tx3_passo2()   3 B  tx3_passo3()   4 B  tx3_passo4()  (si blocca)   5 A  tx3_passo5()
// I 60 s della transazione corrono dal passo 1: se scadono, esegui tx3_prepara() e ricomincia.
// ───────────────────────────────────────────────────────────────────────────────
function tx3_prepara() {
  db.lab_accounts.drop()
  db.lab_accounts.insertMany([ { _id: 'A', balance: NumberDecimal('100.00') }, { _id: 'B', balance: NumberDecimal('50.00') } ])
  print('Preparato: A = 100.00, B = 50.00')
}
function tx3_saldi() { printjson(db.lab_accounts.find().sort({ _id: 1 }).toArray().map(d => ({ _id: d._id, balance: d.balance.toString() }))) }
// 1 · A: in transazione, toglie 10 al conto A → vale 90 SOLO dentro la transazione
function tx3_passo1() {
  globalThis.sA = db.getMongo().startSession(); globalThis.accA = sA.getDatabase('shop').lab_accounts
  sA.startTransaction()
  accA.updateOne({ _id: 'A' }, { $inc: { balance: NumberDecimal('-10.00') } })
  print('A, dentro la transazione:'); printjson(accA.findOne({ _id: 'A' }))                 // → 90.00
}
// 2 · B: legge il conto A, fuori da transazioni → vede ancora 100
function tx3_passo2() { print('B, fuori dalla transazione:'); printjson(db.lab_accounts.findOne({ _id: 'A' })) }
// 3 · B: in transazione, scrive sul conto A → WriteConflict immediato (etichetta TransientTransactionError)
function tx3_passo3() {
  globalThis.sB = db.getMongo().startSession(); globalThis.accB = sB.getDatabase('shop').lab_accounts
  sB.startTransaction()
  try { accB.updateOne({ _id: 'A' }, { $inc: { balance: NumberDecimal('-5.00') } }); print('NESSUN CONFLITTO (la transazione di A è già chiusa?)') }
  catch (e) { print(e.codeName + ' (' + e.code + ') ' + JSON.stringify(e.errorLabels)) }
  try { sB.abortTransaction() } catch (e) {}
}
// 4 · B: fuori da transazioni, scrive sul conto A → RESTA IN ATTESA fino al commit di A
function tx3_passo4() {
  const t0 = Date.now()
  db.lab_accounts.updateOne({ _id: 'A' }, { $inc: { balance: NumberDecimal('-1.00') } })
  print('sbloccato dopo ' + (Date.now() - t0) + ' ms'); tx3_saldi()                          // → A 89.00 (il -1 si applica sul valore già confermato, 90)
}
// 5 · A: commit → B si sblocca
function tx3_passo5() { sA.commitTransaction(); print('commit fatto') }
// In un solo terminale (per provare il conflitto senza il secondo terminale; il passo 4, che si blocca, non c'è):
//   tx3_tutto_in_un_terminale()
function tx3_tutto_in_un_terminale() {
  tx3_prepara(); tx3_passo1(); tx3_passo2()
  tx3_passo3()                                                    // → WriteConflict (112) ["TransientTransactionError"]
  tx3_passo5(); tx3_saldi()                                       // → A 90.00 (il commit di A), B 50.00
  db.lab_accounts.drop()
}


// ───────────────────────────────────────────────────────────────────────────────
// [IX1] Indici: `COLLSCAN`, `IXSCAN` e come leggere `explain`
// L'indice `customerId_1` creato qui RESTA: serve alla demo AG4 (la pulizia è in fondo al file).
// ───────────────────────────────────────────────────────────────────────────────
try { db.orders.dropIndex('customerId_1') } catch (e) {}
riassunto = c => ({ piano: (JSON.stringify(c.explain().queryPlanner.winningPlan).match(/"stage":"[A-Z_]+"/g) || []).map(x => x.slice(9, -1)).join(' ← '),
                    n: c.explain('executionStats').executionStats.nReturned, keys: c.explain('executionStats').executionStats.totalKeysExamined,
                    docs: c.explain('executionStats').executionStats.totalDocsExamined, ms: c.explain('executionStats').executionStats.executionTimeMillis })
// senza indice (output completo di executionStats, come nella slide)
db.orders.find({ customerId: 4242 }).explain('executionStats').executionStats
riassunto(db.orders.find({ customerId: 4242 }))                   // → { piano: 'COLLSCAN', n: 10, keys: 0, docs: 1000000, ms: ~300 }
db.orders.createIndex({ customerId: 1 })
riassunto(db.orders.find({ customerId: 4242 }))                   // → { piano: 'FETCH ← IXSCAN', n: 10, keys: 10, docs: 10, ms: 0 }


// ───────────────────────────────────────────────────────────────────────────────
// [IX3] Indici composti e regola ESR
// ───────────────────────────────────────────────────────────────────────────────
stat = c => { const s = c.explain('executionStats').executionStats; return { n: s.nReturned, keys: s.totalKeysExamined, docs: s.totalDocsExamined } }
piano = c => (JSON.stringify(c.explain().queryPlanner.winningPlan).match(/"stage":"[A-Z_]+"/g) || []).map(x => x.slice(9, -1)).join(' ← ')
// status = 'pending', total >= 500, ordinati per createdAt (desc), primi 10
q = () => db.orders.find({ status: 'pending', total: { $gte: NumberDecimal('500') } }).sort({ createdAt: -1 }).limit(10)
db.orders.createIndex({ status: 1, total: 1, createdAt: 1 }, { name: 'ERS' })      // E-R-S: il range prima del sort
db.orders.createIndex({ status: 1, createdAt: 1, total: 1 }, { name: 'ESR' })      // E-S-R
stat(q().hint('ERS'))              // → { n: 10, keys: 1046, docs: 10 }   (c'è uno stage SORT in memoria)
piano(q().hint('ERS'))
stat(q().hint('ESR'))              // → { n: 10, keys: 17, docs: 10 }     (nessun SORT: le chiavi escono già ordinate)
piano(q().hint('ESR'))
piano(q())                         // senza hint il planner sceglie da solo l'E-S-R
db.orders.dropIndex('ERS'); db.orders.dropIndex('ESR')


// ───────────────────────────────────────────────────────────────────────────────
// [IX4] Multikey, unique, partial, TTL
// ───────────────────────────────────────────────────────────────────────────────
stat = c => { const s = c.explain('executionStats').executionStats; return { n: s.nReturned, keys: s.totalKeysExamined, docs: s.totalDocsExamined } }
// multikey: una voce per elemento dell'array
db.orders.createIndex({ tags: 1 })
stat(db.orders.find({ tags: 'vip' }))                               // → { n: 1000, keys: 1000, docs: 1000 }
// al massimo un campo array in un indice composto
db.orders.createIndex({ tags: 1, 'items.sku': 1 })                  // → CannotIndexParallelArrays: cannot index parallel arrays
db.orders.dropIndex('tags_1')
// unique: un documento senza il campo conta come null
db.lab_unique.drop()
db.lab_unique.createIndex({ sku: 1 }, { unique: true })
db.lab_unique.insertOne({ _id: 1 })                                 // → accettato
db.lab_unique.insertOne({ _id: 2 })                                 // → E11000 duplicate key ... { sku: null }
// con un indice unique PARTIAL due documenti senza il campo convivono
db.lab_unique.drop()
db.lab_unique.createIndex({ sku: 1 }, { unique: true, partialFilterExpression: { sku: { $exists: true } } })
db.lab_unique.insertMany([ { _id: 1 }, { _id: 2 } ])                // → accettati
// la creazione di un indice unique FALLISCE se ci sono già duplicati
db.orders.createIndex({ customerId: 1 }, { unique: true, name: 'cid_unique' })    // → E11000 duplicate key
// partial: indicizza solo gli ordini pending
db.orders.createIndex({ createdAt: 1 }, { partialFilterExpression: { status: 'pending' }, name: 'createdAt_pending' })
stat(db.orders.find({ status: 'pending' }).sort({ createdAt: -1 }).limit(5))        // → { n: 5, keys: 5, docs: 5 }
stat(db.orders.find({ status: 'paid' }).sort({ createdAt: -1 }).limit(5))           // → { n: 5, keys: 0, docs: 1000000 }  (COLLSCAN + SORT)
db.orders.dropIndex('createdAt_pending')
// TTL: solo campi Date; una data come stringa non scade mai; il processo gira ogni 60 s
db.lab_sessions.drop()
db.lab_sessions.insertMany([ { _id: 'old', createdAt: new Date(Date.now() - 2 * 3600 * 1000) }, { _id: 'new', createdAt: new Date() }, { _id: 'str', createdAt: '2020-01-01' } ])
db.lab_sessions.createIndex({ createdAt: 1 }, { expireAfterSeconds: 3600 })
db.lab_sessions.find({}, { _id: 1 })                                // → old, new, str  (subito dopo la creazione)
// ... dopo 60-65 secondi, rilancia la find:
// db.lab_sessions.find({}, { _id: 1 })                             // → new, str  (old eliminato; la stringa non scade mai)


// ───────────────────────────────────────────────────────────────────────────────
// [IX5] Covered query, plan cache, costo degli indici
// ───────────────────────────────────────────────────────────────────────────────
stat = c => { const s = c.explain('executionStats').executionStats; return { n: s.nReturned, keys: s.totalKeysExamined, docs: s.totalDocsExamined } }
piano = c => (JSON.stringify(c.explain().queryPlanner.winningPlan).match(/"stage":"[A-Z_]+"/g) || []).map(x => x.slice(9, -1)).join(' ← ')
db.orders.createIndex({ customerId: 1 })                            // già presente dopo IX1: è idempotente
// covered: filtro e proiezione solo su campi dell'indice, senza _id
stat(db.orders.find({ customerId: 4242 }, { _id: 0, customerId: 1 }))                   // → { n: 10, keys: 10, docs: 0 }
piano(db.orders.find({ customerId: 4242 }, { _id: 0, customerId: 1 }))                  // → PROJECTION_COVERED ← IXSCAN
// un campo in più nella proiezione e la covered query è persa
stat(db.orders.find({ customerId: 4242 }, { _id: 0, customerId: 1, total: 1 }))         // → { n: 10, keys: 10, docs: 10 }
piano(db.orders.find({ customerId: 4242 }, { _id: 0, customerId: 1, total: 1 }))        // → PROJECTION_SIMPLE ← FETCH ← IXSCAN
// plan cache: con due indici candidati la voce nasce INATTIVA e si attiva alla seconda esecuzione
db.orders.createIndex({ tags: 1 })
db.orders.getPlanCache().clear()
db.orders.find({ customerId: 4242, tags: 'promo' }).toArray().length
db.orders.getPlanCache().list().map(x => ({ attiva: x.isActive }))                      // → [ { attiva: false } ]
db.orders.find({ customerId: 4242, tags: 'promo' }).toArray().length
db.orders.getPlanCache().list().map(x => ({ attiva: x.isActive }))                      // → [ { attiva: true } ]
// costo: quante volte è stato usato ogni indice (contatori per nodo, ripartono al riavvio)
db.orders.aggregate([ { $indexStats: {} }, { $project: { name: 1, ops: '$accesses.ops' } } ])
db.orders.dropIndex('tags_1')


// ───────────────────────────────────────────────────────────────────────────────
// [AG1] Pipeline e stage: `find` vs `aggregate` e l'ordine logico SQL
// ───────────────────────────────────────────────────────────────────────────────
db.orders.aggregate([
  { $match: { status: 'delivered' } },                  // filtra
  { $group: { _id: '$customerId', n: { $sum: 1 } } },    // raggruppa
  { $sort: { n: -1 } },                                  // ordina
  { $limit: 5 }                                          // limita
])
// le espressioni: '$items.qty' su un array è l'array delle quantità
db.orders.aggregate([ { $match: { _id: 1 } }, { $project: { quantita: '$items.qty', righe: { $size: '$items' }, pezzi: { $sum: '$items.qty' } } } ])   // → quantita [4, 2], righe 2, pezzi 6


// ───────────────────────────────────────────────────────────────────────────────
// [AG2] `$group`, `$project`/`$set`, `HAVING`
// ───────────────────────────────────────────────────────────────────────────────
db.orders.aggregate([ { $group: { _id: '$status', n: { $sum: 1 } } }, { $sort: { n: -1 } } ])
// → [ { _id: 'delivered', n: 899915 }, { _id: 'shipped', n: 59772 }, { _id: 'paid', n: 30272 },
//     { _id: 'cancelled', n: 8047 }, { _id: 'pending', n: 1994 } ]
db.orders.aggregate([ { $group: { _id: '$customerId', ordini: { $sum: 1 } } }, { $match: { ordini: { $gte: 25 } } }, { $sort: { _id: 1 } } ])
// → [ { _id: 61325, ordini: 25 }, { _id: 61731, ordini: 25 }, { _id: 80617, ordini: 25 } ]
// le date sono in UTC: per un report in ora locale si passa timezone
db.orders.aggregate([ { $match: { _id: 4242 } }, { $project: { createdAt: 1, giornoUTC: { $dateTrunc: { date: '$createdAt', unit: 'day' } },
  giornoRoma: { $dateTrunc: { date: '$createdAt', unit: 'day', timezone: 'Europe/Rome' } } } } ])
// somme di Decimal128 esatte; dopo $toDouble portano l'errore del double
db.orders.aggregate([ { $match: { _id: { $lte: 3 } } }, { $group: { _id: null, dec: { $sum: '$total' }, dbl: { $sum: { $toDouble: '$total' } } } } ])   // → dec 1899.61, dbl 1899.6100000000001


// ───────────────────────────────────────────────────────────────────────────────
// [AG3] `$unwind` e `$lookup`
// ───────────────────────────────────────────────────────────────────────────────
db.orders.aggregate([ { $unwind: '$items' },
  { $group: { _id: '$items.sku', pezzi: { $sum: '$items.qty' }, ricavi: { $sum: { $multiply: ['$items.qty', '$items.unitPrice'] } } } },
  { $sort: { ricavi: -1 } }, { $limit: 3 } ])
// → [ { _id: 'SKU-15', pezzi: 30838, ricavi: Decimal128('1585612.43') }, { _id: 'SKU-13', … }, { _id: 'SKU-25', … } ]
db.orders.aggregate([ { $match: { _id: { $lte: 3 } } },
  { $lookup: { from: 'customers', localField: 'customerId', foreignField: '_id', as: 'cliente' } },
  { $unwind: '$cliente' }, { $project: { email: '$cliente.email', country: '$cliente.country' } } ])
// → [ { _id: 1, email: 'user44830@example.com', country: 'IT' }, { _id: 2, … }, { _id: 3, … } ]
// preserveNullAndEmptyArrays: senza, gli ordini con array vuoto spariscono (INNER JOIN); con, restano (LEFT JOIN)
db.lab_orders.drop()
db.lab_orders.insertMany([ { _id: 'O-1', items: [ { sku: 'P-001', qty: 1 } ] }, { _id: 'O-4', items: [] } ])
db.lab_orders.aggregate([ { $unwind: '$items' }, { $project: { sku: '$items.sku' } } ])                                               // → solo O-1
db.lab_orders.aggregate([ { $unwind: { path: '$items', preserveNullAndEmptyArrays: true } }, { $project: { sku: '$items.sku' } } ])    // → O-1 e O-4


// ───────────────────────────────────────────────────────────────────────────────
// [AG4] Demo: `hideIndex` e `$lookup`
// L'indice `customerId_1` è quello mostrato in IX1 (lo ricrea se manca).
// ATTENZIONE: su MongoDB 8.0.32 i contatori misurati sono 5.000.000 (nascosto) e 50 (visibile),
//             non 5.000.005 e 55 come riportato nella tabella della slide.
// ───────────────────────────────────────────────────────────────────────────────
db.orders.createIndex({ customerId: 1 })
// (nella slide `const`; qui `var`, per poter ripetere il blocco)
var lk = () => db.customers.explain('executionStats').aggregate([
  { $match: { _id: { $lte: 5 } } },
  { $lookup: { from: 'orders', localField: '_id', foreignField: 'customerId', as: 'ordini' } },
  { $project: { n: { $size: '$ordini' } } } ])
// estrae dallo stage $lookup i campi della tabella della slide
campi = e => { const j = JSON.stringify(e); const mx = re => { const v = (j.match(re) || []).map(x => Number(x.split(':')[1])); return v.length ? Math.max(...v) : null }
  return { strategy: (j.match(/"strategy":"([A-Za-z]+)"/) || [])[1], collectionScans: mx(/"collectionScans":\d+/) || 0, totalDocsExamined: mx(/"totalDocsExamined":\d+/), totalKeysExamined: mx(/"totalKeysExamined":\d+/), ms: mx(/"executionTimeMillis":\d+/) } }
db.orders.hideIndex('customerId_1')      // l'indice esiste e si mantiene, ma il planner lo ignora
campi(lk())                               // → { strategy: 'NestedLoopJoin', collectionScans: 5, totalDocsExamined: 5000000, ms: ~1500 }
db.orders.unhideIndex('customerId_1')
campi(lk())                               // → { strategy: 'IndexedLoopJoin', collectionScans: 0, totalDocsExamined: 50, totalKeysExamined: 55, ms: ~0 }
// il risultato della pipeline è identico nei due casi
db.customers.aggregate([ { $match: { _id: { $lte: 5 } } }, { $lookup: { from: 'orders', localField: '_id', foreignField: 'customerId', as: 'ordini' } },
  { $project: { n: { $size: '$ordini' } } } ])     // → n: 14, 9, 6, 13, 8


// ───────────────────────────────────────────────────────────────────────────────
// [AG5] Ottimizzazione: `$match` in testa, memoria, `maxTimeMS`
// ───────────────────────────────────────────────────────────────────────────────
db.orders.createIndex({ customerId: 1 })
docsEsaminati = p => JSON.stringify(db.orders.explain('executionStats').aggregate(p)).match(/"totalDocsExamined":(\d+)/)[1] * 1
// il server sposta da solo un $match prima di un $project che si limita a RINOMINARE il campo...
docsEsaminati([ { $project: { cliente: '$customerId' } }, { $match: { cliente: 4242 } }, { $count: 'n' } ])                                  // → 10
// ...ma non può farlo su un campo CALCOLATO: il $match resta dopo e legge tutto
docsEsaminati([ { $project: { cliente: { $toString: '$customerId' } } }, { $match: { cliente: '4242' } }, { $count: 'n' } ])                  // → 1000000
// memoria: con allowDiskUse: false un $sort su un milione di ordini FALLISCE (limite 100 MB per stage)
db.orders.aggregate([ { $sort: { total: -1, _id: 1 } }, { $skip: 999999 } ], { allowDiskUse: false })       // → QueryExceededMemoryLimitNoDiskUseAllowed
// con $limit dopo $sort è un top-k: resta in pochi KB e non fallisce
db.orders.aggregate([ { $sort: { total: -1, _id: 1 } }, { $limit: 1 }, { $project: { total: 1 } } ], { allowDiskUse: false })
// maxTimeMS: ferma il lavoro sul server (qui un $lookup senza indice su foreignField)
db.orders.hideIndex('customerId_1')
db.customers.aggregate([ { $lookup: { from: 'orders', localField: '_id', foreignField: 'customerId', as: 'o' } } ], { maxTimeMS: 2000 })   // → MaxTimeMSExpired
db.orders.unhideIndex('customerId_1')


// ───────────────────────────────────────────────────────────────────────────────
// [AG6] View: una pipeline con un nome
// ───────────────────────────────────────────────────────────────────────────────
db.orders.createIndex({ customerId: 1 })
db.orders_with_customer.drop()
db.createView('orders_with_customer', 'orders', [
  { $lookup: { from: 'customers', localField: 'customerId', foreignField: '_id', as: 'c' } },
  { $set: { customerName: { $first: '$c.name' } } },
  { $project: { c: 0 } }
])
db.orders_with_customer.find({ customerId: 4242 }, { customerName: 1, total: 1 })        // → 10 ordini, customerName 'Customer 4242'
// il filtro del find si ACCODA alla pipeline: su customerId (campo non modificato) il server lo sposta in testa e usa l'indice di orders
docs = e => Math.max(...(JSON.stringify(e).match(/"totalDocsExamined":\d+/g) || []).map(x => Number(x.split(':')[1])))
docs(db.orders_with_customer.find({ customerId: 4242 }).explain('executionStats'))     // → 20 (10 ordini + 10 clienti del $lookup: non un milione)
// su un campo CALCOLATO (customerName) non può: COLLSCAN su tutti gli ordini, poi $lookup, poi il filtro (qui solo il piano, senza eseguire)
(JSON.stringify(db.orders_with_customer.find({ customerName: 'Customer 4242' }).explain()).match(/\$cursor|COLLSCAN|\$lookup|\$match/g) || [])


// ───────────────────────────────────────────────────────────────────────────────
// [AG7] View o `$merge`: ricalcolare o materializzare
// ───────────────────────────────────────────────────────────────────────────────
db.revenue_by_country.drop()
db.orders.aggregate([
  { $match: { status: 'delivered' } },
  { $group: { _id: '$customer.country', revenue: { $sum: '$total' } } },
  { $merge: { into: 'revenue_by_country', whenMatched: 'replace', whenNotMatched: 'insert' } }
])
// una lettura normale: costo trascurabile, a differenza della pipeline sul milione di ordini
db.revenue_by_country.find().sort({ revenue: -1 })               // → IT 201545381.79, ES 50649145.97, FR 50566133.79, US 50502435.81, GB 50443074.44, DE 50436469.75
// la collezione materializzata ha indici propri
db.revenue_by_country.createIndex({ revenue: -1 })
// un ricalcolo parziale è possibile: si riesegue la pipeline con un $match più stretto e $merge aggiorna solo quei documenti


// ═══════════════════════════════════════════════════════════════════════════════
// PULIZIA: elimina collezioni, indici e view creati dalle demo e ripristina il cliente 4242
// ═══════════════════════════════════════════════════════════════════════════════
['lab_types', 'lab_demo', 'lab_coupon', 'lab_orders', 'lab_products', 'lab_counters', 'lab_students', 'lab_courses', 'lab_enrollments',
 'lab_accounts', 'lab_sessions', 'lab_unique', 'lab_strict', 'lab_del', 'lab_custmers', 'orders_with_customer', 'revenue_by_country'].forEach(c => db[c].drop())
db.orders.getIndexes().filter(i => i.name !== '_id_').forEach(i => { try { db.orders.unhideIndex(i.name) } catch (e) {}; db.orders.dropIndex(i.name) })
db.customers.updateOne({ _id: 4242 }, { $set: { name: 'Customer 4242' } })
db.orders.updateMany({ customerId: 4242, 'customer.name': { $ne: 'Customer 4242' } }, { $set: { 'customer.name': 'Customer 4242' } })
db.orders.getIndexes().map(i => i.name)                           // → [ '_id_' ]
