import java.io.Closeable;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.StringReader;

import java.sql.PreparedStatement;
import java.sql.SQLException;

import org.xmlpull.v1.XmlPullParser;
import org.xmlpull.v1.XmlPullParserException;
import org.xmlpull.v1.XmlPullParserFactory;

/**
 * Bonnes pratiques sur les flux du chargement.
 * Les fichiers XML sont en Latin-1 : l'encodage est impose a l'ouverture.
 * Tout flux est ferme, meme quand la lecture echoue.
 * Un texte trop long pour setString est envoye par un flux de caracteres.
 */
public final class GestionFlux {
    public static final String ENCODAGE_XML = "ISO-8859-1";

    /** Au-dela, le pilote JDBC peut refuser setString. */
    private static final int LIMITE_CHAINE = 32000;

    private GestionFlux() {
    }

    public static InputStream ouvrirFichier(String chemin) throws IOException {
        return new FileInputStream(chemin);
    }

    public static XmlPullParser nouveauParser(InputStream flux) throws XmlPullParserException {
        XmlPullParserFactory factory = XmlPullParserFactory.newInstance();
        XmlPullParser parser = factory.newPullParser();
        parser.setInput(flux, ENCODAGE_XML);
        return parser;
    }

    public static void fermer(Closeable flux) {
        if (flux == null) {
            return;
        }
        try {
            flux.close();
        } catch (IOException e) {
            System.out.println(e.getMessage());
        }
    }

    public static boolean texteTropLongPourChaine(String texte) {
        return texte.length() > LIMITE_CHAINE;
    }

    public static void fixerTexte(PreparedStatement requete, int index, String texte) throws SQLException {
        if (texteTropLongPourChaine(texte)) {
            requete.setCharacterStream(index, new StringReader(texte), texte.length());
        } else {
            requete.setString(index, texte);
        }
    }
}
