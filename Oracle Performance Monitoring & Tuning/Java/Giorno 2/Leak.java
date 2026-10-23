// Laboratorio Giorno 2 - Esercizio 2: provocare un connection leak
//
// Apre 20 connessioni e non le chiude mai, poi resta in attesa 10 minuti
// per permettere di osservarle dal database.
//
// Esecuzione (Java 17+, nella cartella con il driver):
//   java -cp ojdbc11.jar Leak.java
//
// Mentre il programma attende, dal terminale SQL:
//   SELECT status, COUNT(*) FROM v$session WHERE username = 'TUNING_USER' GROUP BY status;
//   SELECT sid, program, status, last_call_et FROM v$session
//   WHERE username = 'TUNING_USER' AND program = 'SourceLauncher' ORDER BY last_call_et DESC;
//
// Interrompere con Ctrl+C: la JVM chiude i socket e le sessioni spariscono.

import java.sql.Connection;
import java.sql.DriverManager;
import java.util.ArrayList;
import java.util.List;

public class Leak {

    static final String URL = "jdbc:oracle:thin:@//localhost:1521/XEPDB1";
    static final String USER = "tuning_user";
    static final String PWD = "tuning_pwd";
    static final int LEAKED = 20;

    public static void main(String[] a) throws Exception {
        List<Connection> perse = new ArrayList<>();   // tenute in una lista solo per non farle raccogliere dal GC

        for (int i = 1; i <= LEAKED; i++) {
            Connection c = DriverManager.getConnection(URL, USER, PWD);
            c.createStatement().executeQuery("SELECT 1 FROM dual");   // ERRORE VOLUTO: nessun close()
            perse.add(c);
            System.out.println("Connessioni aperte e mai chiuse: " + i);
        }

        System.out.println("Ora osservate le sessioni dal database. Attesa di 10 minuti (Ctrl+C per uscire)...");
        Thread.sleep(600_000);

        // Il modo corretto sarebbe stato:
        // try (Connection c = DriverManager.getConnection(URL, USER, PWD);
        //      Statement st = c.createStatement()) { ... }
    }
}
