// ═══════════════════════════════════════════════════════════════════════════════
// genera_database_demo.js · genera il database `shop` di ShopIT per le demo e i laboratori del Giorno 2
//
//   customers   100.000 clienti
//   orders    1.000.000 ordini, con cliente copiato (extended reference), righe annidate, tag e attributi sparsi
//
// È DETERMINISTICO (generatore pseudo-casuale con seme fisso): tutti ottengono gli stessi dati, e quindi gli stessi
// numeri delle slide. Produce lo stesso database del servizio `seed` (scripts/seed.js): è la versione "da portare con sé",
// con avanzamento, verifica integrata e opzioni. Al termine controlla i numeri citati nelle slide (OK / KO).
//
// ESECUZIONE
//   mongosh (consigliato: circa 65 s di generazione + 13 s di verifica su 1 vCPU):
//     docker compose exec mongo mongosh --quiet "mongodb://localhost:27017/?directConnection=true" /scripts/genera_database_demo.js
//   Compass: incolla l'intero file nella shell integrata (in modalità interattiva i tempi raddoppiano: circa 2 minuti).
//
// OPZIONI (definisci GEN_OPZIONI PRIMA di eseguire il file; tutte facoltative):
//   GEN_OPZIONI = { db: 'shop', clienti: 100000, ordini: 1000000, forza: false, pulisciIndici: true, pulisciLab: false, verifica: true }
//     db             nome del database                                                       (default 'shop')
//     clienti/ordini dimensioni; con ordini minori i dati sono i PRIMI ordini del dataset completo
//                    (stessi _id e stesso contenuto), ma i numeri delle slide valgono solo a dimensione piena
//     forza          true = rigenera anche se il dataset è già presente e corretto            (default false)
//     pulisciIndici  elimina gli indici secondari di `orders` (le slide partono senza)        (default true)
//     pulisciLab     elimina le collezioni create dalle demo e dai laboratori (lab_*, view…)  (default false)
//     verifica       esegue i controlli sui numeri delle slide                                (default true)
// ═══════════════════════════════════════════════════════════════════════════════
(function () {
  var G = Object.assign({ db: 'shop', clienti: 100000, ordini: 1000000, forza: false, pulisciIndici: true, pulisciLab: false, verifica: true },
                        (typeof GEN_OPZIONI !== 'undefined') ? GEN_OPZIONI : {})
  var D = db.getSiblingDB(G.db)
  var t0 = Date.now()
  var passato = function () { return Math.round((Date.now() - t0) / 1000) + ' s' }

  // ── generatore pseudo-casuale con seme fisso (mulberry32) ────────────────────────────────────────────────────
  function mulberry32(a) {
    return function () {
      a |= 0; a = a + 0x6D2B79F5 | 0
      var t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t
      return ((t ^ t >>> 14) >>> 0) / 4294967296
    }
  }
  var PAESI = ['IT', 'IT', 'IT', 'IT', 'FR', 'DE', 'ES', 'GB', 'US']
  var CANALI = ['web', 'app', 'store']
  var BATCH = 10000
  var money = function (x) { return NumberDecimal(x.toFixed(2)) }

  function genera() {
    print('Generazione di ' + G.db + ': ' + G.clienti + ' clienti e ' + G.ordini + ' ordini...')
    D.orders.drop(); D.customers.drop()
    var rnd = mulberry32(42)
    var buf = []
    for (var g = 1; g <= G.clienti; g++) {
      buf.push({ _id: NumberInt(g), email: 'user' + g + '@example.com', name: 'Customer ' + g, country: PAESI[g % 9] })
      if (buf.length === BATCH) { D.customers.insertMany(buf, { ordered: false, writeConcern: { w: 1 } }); buf = [] }
    }
    if (buf.length) { D.customers.insertMany(buf, { ordered: false, writeConcern: { w: 1 } }); buf = [] }
    print('  customers: ' + D.customers.estimatedDocumentCount() + ' (' + passato() + ')')
    var inizio = Date.UTC(2026, 0, 1)
    for (g = 1; g <= G.ordini; g++) {
      var r = rnd()
      var status = r < 0.90 ? 'delivered' : r < 0.96 ? 'shipped' : r < 0.99 ? 'paid' : r < 0.998 ? 'cancelled' : 'pending'
      var cid = 1 + Math.floor(rnd() * 100000)
      var tags = g % 1000 === 0 ? ['vip', 'express'] : g % 7 === 0 ? ['gift', 'express'] : g % 5 === 0 ? ['promo'] : []
      var attrs = { channel: CANALI[g % 3] }
      if (g % 10 === 0) attrs.coupon = 'SPRING'
      if (g % 5000 === 0) attrs.risk = 'high'
      var items = []
      for (var l = 1; l <= 1 + (g % 3); l++)
        items.push({ lineNo: NumberInt(l), sku: 'SKU-' + (1 + Math.floor(rnd() * 200)), qty: NumberInt(1 + Math.floor(rnd() * 5)), unitPrice: money(1 + rnd() * 100) })
      buf.push({ _id: NumberInt(g), customerId: NumberInt(cid), customer: { name: 'Customer ' + cid, country: PAESI[cid % 9] },
                 status: status, total: money(10 + rnd() * 990), createdAt: new Date(inizio + g * 30000), tags: tags, attrs: attrs, items: items })
      if (buf.length === BATCH) {
        D.orders.insertMany(buf, { ordered: false, writeConcern: { w: 1 } }); buf = []
        if (g % 100000 === 0) print('  orders: ' + g + ' (' + passato() + ')')
      }
    }
    if (buf.length) D.orders.insertMany(buf, { ordered: false, writeConcern: { w: 1 } })
    D.customers.createIndex({ email: 1 }, { unique: true })
    print('  generazione completata in ' + passato())
  }

  // ── il dataset è già presente e corretto? (stesse dimensioni e primo ordine uguale a quello delle slide) ─────────
  function presente() {
    if (D.customers.estimatedDocumentCount() !== G.clienti || D.orders.estimatedDocumentCount() !== G.ordini) return false
    var o = D.orders.findOne({ _id: 1 })
    return !!o && o.customerId === 44830 && o.total.toString() === '866.82'
  }
  if (G.forza || !presente()) genera(); else print('Il dataset ' + G.db + ' è già presente e corretto: nessuna rigenerazione (forza: true per rigenerarlo).')

  // ── riporta il database allo stato di partenza delle slide ─────────────────────────────────────────────────────
  if (G.pulisciIndici) D.orders.getIndexes().filter(function (i) { return i.name !== '_id_' }).forEach(function (i) { try { D.orders.unhideIndex(i.name) } catch (e) {}; D.orders.dropIndex(i.name) })
  if (G.pulisciLab) D.getCollectionNames().filter(function (n) { return n.indexOf('lab_') === 0 || ['orders_with_customer', 'revenue_by_country', 'customer_stats'].indexOf(n) >= 0 }).forEach(function (n) { D[n].drop() })
  D.customers.updateOne({ _id: 4242 }, { $set: { name: 'Customer 4242' } })                                   // le demo rinominano il cliente 4242 e lo ripristinano
  D.orders.updateMany({ customerId: 4242, 'customer.name': { $ne: 'Customer 4242' } }, { $set: { 'customer.name': 'Customer 4242' } })

  // ── verifica dei numeri citati nelle slide ───────────────────────────────────────────────────────────────────────
  if (!G.verifica) { print('Verifica disattivata.'); return }
  var ko = 0
  var ok = function (msg, cond, atteso, trovato) { print((cond ? 'OK  - ' : 'KO  - ') + msg + (cond ? '' : ' (atteso ' + atteso + ', trovato ' + trovato + ')')); if (!cond) ko++ }
  var uguale = function (msg, trovato, atteso) { ok(msg, JSON.stringify(trovato) === JSON.stringify(atteso), JSON.stringify(atteso), JSON.stringify(trovato)) }
  print('\nVerifica dei numeri delle slide su ' + G.db + ':')
  uguale('[O2] clienti e ordini', [D.customers.countDocuments({}), D.orders.countDocuments({})], [G.clienti, G.ordini])
  uguale('[N/E] tipi: _id int, total Decimal128, createdAt Date, qty int',
         [D.orders.countDocuments({ _id: { $not: { $type: 'int' } } }), D.orders.countDocuments({ total: { $not: { $type: 'decimal' } } }),
          D.orders.countDocuments({ createdAt: { $not: { $type: 'date' } } }), D.orders.countDocuments({ 'items.qty': { $not: { $type: 'int' } } })], [0, 0, 0, 0])
  uguale('indici: orders solo _id (le slide partono senza indici secondari)', D.orders.getIndexes().map(function (i) { return i.name }), ['_id_'])
  ok('indici: customers ha email_1 unique', D.customers.getIndexes().some(function (i) { return i.name === 'email_1' && i.unique === true }), 'email_1 unique', JSON.stringify(D.customers.getIndexes().map(function (i) { return i.name })))
  var o1 = D.orders.findOne({ _id: 1 })
  uguale('[O2] ordine 1: cliente, stato, totale, data, canale',
         [o1.customerId, o1.status, o1.total.toString(), o1.createdAt.toISOString(), o1.attrs.channel], [44830, 'delivered', '866.82', '2026-01-01T00:00:30.000Z', 'app'])
  uguale('[O2] ordine 1: righe', o1.items.map(function (i) { return i.sku + ' x' + i.qty + ' ' + i.unitPrice.toString() }), ['SKU-171 x4 18.48', 'SKU-106 x2 63.47'])
  uguale('[B4] bsonsize(ordine 1)', bsonsize(o1), 348)
  if (G.clienti !== 100000 || G.ordini !== 1000000) { print('Dataset ridotto: le verifiche numeriche sulle quantità sono saltate.'); print(ko === 0 ? '\nVERIFICA STRUTTURALE OK' : '\n' + ko + ' verifiche fallite'); return }
  uguale('[M6] ordine 4242 e ordini dei clienti 4242 e 44830', [D.orders.findOne({ _id: 4242 }).customerId, D.orders.countDocuments({ customerId: 4242 }), D.orders.countDocuments({ customerId: 44830 })], [46064, 10, 11])
  uguale('[B4] canale web: dot notation e sottodocumento intero', [D.orders.countDocuments({ 'attrs.channel': 'web' }), D.orders.countDocuments({ attrs: { channel: 'web' } })], [333333, 300000])
  uguale('[F1] attrs.risk: presente, $nin, $exists + $ne', [D.orders.countDocuments({ 'attrs.risk': { $exists: true } }), D.orders.countDocuments({ 'attrs.risk': { $nin: ['high'] } }), D.orders.countDocuments({ 'attrs.risk': { $exists: true, $ne: 'high' } })], [200, 999800, 0])
  uguale('[F1/F3] tag: promo, gift, express, vip, vuoti, almeno 2', ['promo', 'gift', 'express', 'vip'].map(function (t) { return D.orders.countDocuments({ tags: t }) }).concat([D.orders.countDocuments({ tags: { $size: 0 } }), D.orders.countDocuments({ 'tags.1': { $exists: true } })]), [170571, 142715, 143715, 1000, 685714, 143715])
  uguale('[AG2] ordini per stato', D.orders.aggregate([{ $group: { _id: '$status', n: { $sum: 1 } } }, { $sort: { n: -1 } }]).toArray().map(function (x) { return x._id + '=' + x.n }), ['delivered=899915', 'shipped=59772', 'paid=30272', 'cancelled=8047', 'pending=1994'])
  uguale('[AG2] clienti con almeno 25 ordini', D.orders.aggregate([{ $group: { _id: '$customerId', n: { $sum: 1 } } }, { $match: { n: { $gte: 25 } } }, { $sort: { _id: 1 } }]).toArray().map(function (x) { return x._id }), [61325, 61731, 80617])
  uguale('[AG3] ricavi per sku: i primi tre', D.orders.aggregate([{ $unwind: '$items' }, { $group: { _id: '$items.sku', pezzi: { $sum: '$items.qty' }, ricavi: { $sum: { $multiply: ['$items.qty', '$items.unitPrice'] } } } }, { $sort: { ricavi: -1 } }, { $limit: 3 }]).toArray().map(function (x) { return x._id + ' ' + x.pezzi + ' ' + x.ricavi.toString() }), ['SKU-15 30838 1585612.43', 'SKU-13 30738 1584347.36', 'SKU-25 30606 1574806.27'])
  uguale('[AG7] fatturato per paese degli ordini delivered', D.orders.aggregate([{ $match: { status: 'delivered' } }, { $group: { _id: '$customer.country', f: { $sum: '$total' } } }, { $sort: { f: -1 } }]).toArray().map(function (x) { return x._id + ' ' + x.f.toString() }), ['IT 201545381.79', 'ES 50649145.97', 'FR 50566133.79', 'US 50502435.81', 'GB 50443074.44', 'DE 50436469.75'])
  print(ko === 0 ? '\nDATABASE PRONTO PER LE DEMO (' + passato() + ')' : '\n' + ko + ' verifiche fallite: il dataset non coincide con quello delle slide')
})()
