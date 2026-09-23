/**
 * Point d'entree du chargement Webflix.
 *
 * Ordre : T2 - Tables.sql, ce programme, puis T3 - Contraintes.sql.
 * L'enonce compte 21550 clients avant les triggers et les CHECK.
 *
 * javac -encoding UTF-8 -cp "ojdbc11.jar;xmlpull_1_1_3_4c.jar;xpp3-1.1.3.4.C.jar" *.java
 * java -cp ".;ojdbc11.jar;xmlpull_1_1_3_4c.jar;xpp3-1.1.3.4.C.jar" Main personnes.xml films.xml clients.xml
 */
public class Main {
    public static void main(String[] args) {
        if (args.length < 3) {
            System.out.println("Usage : java Main <personnes.xml> <films.xml> <clients.xml>");
            return;
        }
        EcritureBD ecriture = new EcritureBD();
        LectureXML lecture = new LectureXML(ecriture);
        try {
            lecture.lirePersonnes(args[0]);
            lecture.lireFilms(args[1]);
            lecture.lireClients(args[2]);
        } finally {
            ecriture.fermer();
        }
    }
}
