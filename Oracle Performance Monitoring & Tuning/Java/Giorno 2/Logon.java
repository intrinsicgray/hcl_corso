// Laboratorio Giorno 2 - Esercizio 1: quanto costa un logon?
//
// Confronta 100 connessioni fisiche (una per query) con 1 connessione riusata per 100 query.
//
// Esecuzione (Java 17+, nella cartella con il driver):
//   java -cp ojdbc11.jar Logon.java
//
// Dal terminale SQL, prima e dopo l'esecuzione:
//   SELECT value FROM v$sysstat WHERE name = 'logons cumulative';
// La differenza sarà di circa 101 logon in più rispetto a quelle già attive nella sessione

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;

public class Logon {

    static final String URL = "jdbc:oracle:thin:@//localhost:1521/XEPDB1";
    static final String USER = "tuning_user";
    static final String PWD = "tuning_pwd";
    static final int N = 100;

    public static void main(String[] a) throws Exception {
        // 1. Una connessione fisica nuova per ogni query
        long t0 = System.nanoTime();
        for (int i = 0; i < N; i++) {
            try (Connection c = DriverManager.getConnection(URL, USER, PWD);
                 Statement st = c.createStatement()) {
                st.execute("SELECT 1 FROM dual");
            }
        }
        long t1 = System.nanoTime();

        // 2. Una sola connessione riusata per tutte le query
        try (Connection c = DriverManager.getConnection(URL, USER, PWD);
             Statement st = c.createStatement()) {
            for (int i = 0; i < N; i++) {
                st.execute("SELECT 1 FROM dual");
            }
        }
        long t2 = System.nanoTime();

        long msMany = (t1 - t0) / 1_000_000;
        long msOne = (t2 - t1) / 1_000_000;
        System.out.printf("%d connessioni:        %6d ms  (%.1f ms per logon+query)%n", N, msMany, msMany / (double) N);
        System.out.printf("1 connessione riusata: %6d ms  (%.1f ms per query)%n", msOne, msOne / (double) N);
        if (msOne > 0) {
            System.out.printf("Rapporto: %.0f volte più lento aprire una connessione per query%n", msMany / (double) msOne);
        }
    }
}
