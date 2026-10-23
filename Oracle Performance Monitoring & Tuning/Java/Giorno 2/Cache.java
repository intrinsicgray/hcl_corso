// Laboratorio Giorno 2 - Esercizio 3: contare i parse con e senza statement cache
//
// Esegue 5.000 volte la stessa PreparedStatement e stampa le statistiche di parse
// della propria sessione (V$MYSTAT).
//
// Prerequisito: chiave primaria su CLIENTI (creata nel lab della mattina):
//   ALTER TABLE clienti ADD CONSTRAINT pk_clienti PRIMARY KEY (cliente_id);
//
// Esecuzione (Java 17+, nella cartella con il driver):
//   java -cp ojdbc11.jar Cache.java       -> senza statement cache
//   java -cp ojdbc11.jar Cache.java on    -> con statement cache implicita
//
// Atteso: senza cache "parse count (total)" circa 5.000; con la cache poche unità.
// In entrambi i casi "parse count (hard)" resta basso grazie alle bind variable.

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import oracle.jdbc.OracleConnection;

public class Cache {

    static final String URL = "jdbc:oracle:thin:@//localhost:1521/XEPDB1";
    static final String USER = "tuning_user";
    static final String PWD = "tuning_pwd";
    static final int N = 5000;

    public static void main(String[] a) throws Exception {
        boolean cache = a.length > 0 && a[0].equalsIgnoreCase("on");

        try (Connection c = DriverManager.getConnection(URL, USER, PWD)) {
            OracleConnection oc = c.unwrap(OracleConnection.class);
            oc.setImplicitCachingEnabled(cache);
            oc.setStatementCacheSize(20);

            long t0 = System.nanoTime();
            for (int i = 1; i <= N; i++) {
                // close() a ogni giro: con la cache attiva il driver NON chiude il cursore sul server, lo riusa
                try (PreparedStatement ps = c.prepareStatement("SELECT nome FROM clienti WHERE cliente_id = ?")) {
                    ps.setInt(1, i);
                    try (ResultSet rs = ps.executeQuery()) {
                        while (rs.next()) { /* niente */ }
                    }
                }
            }
            long ms = (System.nanoTime() - t0) / 1_000_000;

            System.out.printf("Statement cache: %s | %d esecuzioni in %d ms%n", cache ? "ATTIVA" : "disattivata", N, ms);

            String stats = "SELECT n.name, m.value FROM v$mystat m"
                    + " JOIN v$statname n ON m.statistic# = n.statistic#"
                    + " WHERE n.name IN ('parse count (total)', 'parse count (hard)', 'session cursor cache hits', 'execute count')"
                    + " ORDER BY n.name";
            try (PreparedStatement ps = c.prepareStatement(stats);
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    System.out.printf("  %-28s = %d%n", rs.getString(1), rs.getLong(2));
                }
            }
        }
    }
}
