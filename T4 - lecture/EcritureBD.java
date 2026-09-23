import java.sql.Connection;
import java.sql.Date;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

import java.time.DateTimeException;
import java.time.YearMonth;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Insertions Oracle du chargement Webflix.
 * PreparedStatement et addBatch evitent les problemes de caracteres reserves
 * et limitent les allers-retours vers la base.
 *
 * Une personne ou un film dont un champ obligatoire manque n'est pas insere.
 * Le CVV, absent des XML, est genere. Chaque film insere recoit 1 a 100 copies.
 */
public class EcritureBD {
    // A adapter a l'instance Oracle du cours.
    private static final String URL_BD = "jdbc:oracle:thin:@//localhost:1521/XEPDB1";
    private static final String UTILISATEUR_BD = "LOG660";
    private static final String MOT_DE_PASSE_BD = "LOG660";
    private static final int TAILLE_LOT = 500;

    private Connection connexion;

    private PreparedStatement psPersonne;
    private PreparedStatement psGenre;
    private PreparedStatement psPays;
    private PreparedStatement psFilm;
    private PreparedStatement psFilmGenre;
    private PreparedStatement psFilmPays;
    private PreparedStatement psInterpretation;
    private PreparedStatement psScenariste;
    private PreparedStatement psAnnonce;
    private PreparedStatement psCopie;
    private PreparedStatement psUtilisateur;
    private PreparedStatement psAdresse;
    private PreparedStatement psClient;
    private PreparedStatement psCarte;

    private int lotPersonnes;
    private int lotFilmGenre;
    private int lotFilmPays;
    private int lotInterpretations;
    private int lotScenaristes;
    private int lotAnnonces;
    private int lotCopies;
    private int lotClients;

    private int personnesLues;
    private int personnesInserees;
    private int personnesRejetees;
    private int filmsLus;
    private int filmsInseres;
    private int filmsRejetesChamp;
    private int filmsRejetesRealisateur;
    private int rolesIgnores;
    private int scenaristesIgnores;
    private int clientsLus;
    private int clientsInseres;
    private int clientsRejetes;
    private int copiesCreees;

    private final HashSet<Integer> personnesInsereesIds = new HashSet<Integer>();
    private final HashMap<String, Integer> idParNom = new HashMap<String, Integer>();
    private final List<Integer> idsPersonneEnAttente = new ArrayList<Integer>();
    private final List<String> nomsPersonneEnAttente = new ArrayList<String>();
    private final HashSet<String> genresConnus = new HashSet<String>();
    private final HashSet<String> paysConnus = new HashSet<String>();
    private final List<String> genresDuFilm = new ArrayList<String>();
    private final List<String> paysDuFilm = new ArrayList<String>();

    public EcritureBD() {
        connecter();
    }

    public boolean estConnectee() {
        return connexion != null;
    }

    public void insererPersonne(int id, String nom, String anniv, String lieu, String photo, String bio) {
        personnesLues++;
        String nomNet = texte(nom);
        String lieuNet = texte(lieu);
        String photoNet = texte(photo);
        String bioNet = texte(bio);
        Date naissance = lireDate(anniv);
        if (nomNet == null || lieuNet == null || photoNet == null || bioNet == null || naissance == null
                || nomNet.length() > 60 || lieuNet.length() > 120 || photoNet.length() > 200) {
            personnesRejetees++;
            return;
        }
        try {
            if (GestionFlux.texteTropLongPourChaine(bioNet)) {
                terminerLotPersonnes();
                remplirPersonne(id, nomNet, naissance, lieuNet, photoNet, bioNet);
                psPersonne.executeUpdate();
                connexion.commit();
                retenirPersonne(id, nomNet);
            } else {
                remplirPersonne(id, nomNet, naissance, lieuNet, photoNet, bioNet);
                psPersonne.addBatch();
                idsPersonneEnAttente.add(id);
                nomsPersonneEnAttente.add(nomNet);
                lotPersonnes++;
                if (lotPersonnes >= TAILLE_LOT) {
                    terminerLotPersonnes();
                }
            }
        } catch (SQLException e) {
            personnesRejetees++;
            annuler(e, "personne " + id);
        }
    }

    public void insererFilm(int id, String titre, int annee,
            ArrayList<String> pays, String langue, int duree, String resume,
            ArrayList<String> genres, String realisateurNom, int realisateurId,
            ArrayList<String> scenaristes,
            ArrayList<LectureXML.Role> roles, String poster,
            ArrayList<String> annonces) {
        filmsLus++;
        String titreNet = texte(titre);
        String langueNet = texte(langue);
        String resumeNet = texte(resume);
        String posterNet = texte(poster);
        if (titreNet == null || langueNet == null || resumeNet == null || posterNet == null
                || annee < 0 || duree < 0 || realisateurId < 0
                || titreNet.length() > 120 || langueNet.length() > 30
                || resumeNet.length() > 1000 || posterNet.length() > 200) {
            filmsRejetesChamp++;
            return;
        }
        if (!personnesInsereesIds.contains(realisateurId)) {
            filmsRejetesRealisateur++;
            return;
        }
        try {
            psFilm.setInt(1, id);
            psFilm.setInt(2, realisateurId);
            psFilm.setString(3, titreNet);
            psFilm.setInt(4, annee);
            psFilm.setInt(5, duree);
            psFilm.setString(6, langueNet);
            psFilm.setString(7, resumeNet);
            psFilm.setString(8, posterNet);
            psFilm.executeUpdate();

            insererGenres(id, genres);
            insererPays(id, pays);
            insererRoles(id, roles);
            insererScenaristes(id, scenaristes);
            insererAnnonces(id, annonces);
            int copiesAvant = copiesCreees;
            insererCopies(id);
            try {
                validerFilm();
                filmsInseres++;
            } catch (SQLException e) {
                copiesCreees = copiesAvant;
                throw e;
            }
        } catch (SQLException e) {
            filmsRejetesChamp++;
            oublierReferentielsDuFilm();
            viderTamponsFilms();
            annuler(e, "film " + id);
        }
    }

    public void insererClient(int id, String nomFamille, String prenom,
            String courriel, String tel, String anniv,
            String adresse, String ville, String province,
            String codePostal, String carte, String noCarte,
            int expMois, int expAnnee, String motDePasse,
            String forfait) {
        clientsLus++;
        String nomNet = texte(nomFamille);
        String prenomNet = texte(prenom);
        String courrielNet = texte(courriel);
        String telNet = texte(tel);
        String villeNet = texte(ville);
        String provinceNet = texte(province);
        String codePostalNet = texte(codePostal);
        String carteNet = texte(carte);
        String noCarteNet = texte(noCarte);
        String forfaitNet = texte(forfait);
        Date naissance = lireDate(anniv);
        String[] voie = separerAdresse(adresse);
        if (nomNet == null || prenomNet == null || courrielNet == null || telNet == null
                || villeNet == null || provinceNet == null || codePostalNet == null
                || carteNet == null || noCarteNet == null || motDePasse == null
                || motDePasse.trim().isEmpty() || forfaitNet == null || naissance == null
                || voie == null || expMois < 1 || expMois > 12 || expAnnee < 1
                || nomNet.length() > 40 || prenomNet.length() > 40 || courrielNet.length() > 80
                || telNet.length() > 20 || villeNet.length() > 40 || provinceNet.length() > 2
                || codePostalNet.length() > 7 || carteNet.length() > 10 || noCarteNet.length() > 19
                || motDePasse.length() > 50 || forfaitNet.length() > 1) {
            clientsRejetes++;
            return;
        }
        Date expiration;
        try {
            expiration = Date.valueOf(YearMonth.of(expAnnee, expMois).atEndOfMonth());
        } catch (DateTimeException e) {
            clientsRejetes++;
            return;
        }
        String cvv = String.format("%03d", ThreadLocalRandom.current().nextInt(0, 1000));
        try {
            psUtilisateur.setInt(1, id);
            psUtilisateur.setString(2, nomNet);
            psUtilisateur.setString(3, prenomNet);
            psUtilisateur.setString(4, courrielNet);
            psUtilisateur.setString(5, telNet);
            psUtilisateur.setDate(6, naissance);
            psUtilisateur.setString(7, motDePasse);
            psUtilisateur.addBatch();

            psAdresse.setInt(1, id);
            psAdresse.setString(2, voie[0]);
            psAdresse.setString(3, voie[1]);
            psAdresse.setString(4, villeNet);
            psAdresse.setString(5, provinceNet);
            psAdresse.setString(6, codePostalNet);
            psAdresse.addBatch();

            psClient.setInt(1, id);
            psClient.setString(2, forfaitNet);
            psClient.addBatch();

            psCarte.setInt(1, id);
            psCarte.setString(2, carteNet);
            psCarte.setString(3, noCarteNet);
            psCarte.setDate(4, expiration);
            psCarte.setString(5, cvv);
            psCarte.addBatch();

            lotClients++;
            clientsInseres++;
            if (lotClients >= TAILLE_LOT) {
                terminerLotClients();
            }
        } catch (SQLException e) {
            clientsRejetes++;
            annuler(e, "client " + id);
        }
    }

    public void terminerLotPersonnes() {
        if (connexion == null || lotPersonnes == 0) {
            return;
        }
        try {
            psPersonne.executeBatch();
            connexion.commit();
            for (int i = 0; i < idsPersonneEnAttente.size(); i++) {
                retenirPersonne(idsPersonneEnAttente.get(i), nomsPersonneEnAttente.get(i));
            }
            idsPersonneEnAttente.clear();
            nomsPersonneEnAttente.clear();
            lotPersonnes = 0;
        } catch (SQLException e) {
            personnesRejetees += lotPersonnes;
            idsPersonneEnAttente.clear();
            nomsPersonneEnAttente.clear();
            lotPersonnes = 0;
            viderTampon(psPersonne);
            annuler(e, "lot de personnes");
        }
    }

    public void terminerLotsFilms() {
        if (connexion == null) {
            return;
        }
        if (lotFilmGenre + lotFilmPays + lotInterpretations + lotScenaristes + lotAnnonces + lotCopies == 0) {
            return;
        }
        try {
            validerFilm();
        } catch (SQLException e) {
            oublierReferentielsDuFilm();
            viderTamponsFilms();
            annuler(e, "lot de films");
        }
    }

    public void terminerLotClients() {
        if (connexion == null || lotClients == 0) {
            return;
        }
        try {
            psUtilisateur.executeBatch();
            psAdresse.executeBatch();
            psClient.executeBatch();
            psCarte.executeBatch();
            connexion.commit();
            lotClients = 0;
        } catch (SQLException e) {
            clientsInseres -= lotClients;
            clientsRejetes += lotClients;
            lotClients = 0;
            viderTampon(psUtilisateur);
            viderTampon(psAdresse);
            viderTampon(psClient);
            viderTampon(psCarte);
            annuler(e, "lot de clients");
        }
    }

    public void afficherPersonnes() {
        System.out.println("Personnes lues : " + personnesLues
                + ", inserees : " + personnesInserees
                + ", rejetees (champ obligatoire absent) : " + personnesRejetees);
    }

    public void afficherFilms() {
        System.out.println("Films lus : " + filmsLus
                + ", inseres : " + filmsInseres
                + ", rejetes (champ obligatoire absent) : " + filmsRejetesChamp
                + ", rejetes (realisateur non insere) : " + filmsRejetesRealisateur);
        System.out.println("Roles ignores : " + rolesIgnores
                + ", scenaristes ignores : " + scenaristesIgnores
                + ", copies creees : " + copiesCreees);
    }

    public void afficherClients() {
        System.out.println("Clients lus : " + clientsLus
                + ", inseres : " + clientsInseres
                + ", rejetes : " + clientsRejetes);
    }

    public void fermer() {
        PreparedStatement[] requetes = {
            psPersonne, psGenre, psPays, psFilm, psFilmGenre, psFilmPays,
            psInterpretation, psScenariste, psAnnonce, psCopie,
            psUtilisateur, psAdresse, psClient, psCarte
        };
        for (PreparedStatement requete : requetes) {
            if (requete != null) {
                try {
                    requete.close();
                } catch (SQLException e) {
                    System.out.println(e.getMessage());
                }
            }
        }
        if (connexion != null) {
            try {
                connexion.close();
            } catch (SQLException e) {
                System.out.println(e.getMessage());
            }
        }
    }

    private void remplirPersonne(int id, String nom, Date naissance, String lieu, String photo, String bio)
            throws SQLException {
        psPersonne.setInt(1, id);
        psPersonne.setString(2, nom);
        psPersonne.setDate(3, naissance);
        psPersonne.setString(4, lieu);
        psPersonne.setString(5, photo);
        GestionFlux.fixerTexte(psPersonne, 6, bio);
    }

    private void insererGenres(int idFilm, ArrayList<String> genres) throws SQLException {
        HashSet<String> vus = new HashSet<String>();
        for (String genre : genres) {
            String nom = texte(genre);
            if (nom == null || nom.length() > 20 || !vus.add(nom)) {
                continue;
            }
            if (genresConnus.add(nom)) {
                psGenre.setString(1, nom);
                psGenre.executeUpdate();
                genresDuFilm.add(nom);
            }
            psFilmGenre.setInt(1, idFilm);
            psFilmGenre.setString(2, nom);
            psFilmGenre.addBatch();
            lotFilmGenre++;
        }
    }

    private void insererPays(int idFilm, ArrayList<String> pays) throws SQLException {
        HashSet<String> vus = new HashSet<String>();
        for (String paysNom : pays) {
            String nom = texte(paysNom);
            if (nom == null || nom.length() > 30 || !vus.add(nom)) {
                continue;
            }
            if (paysConnus.add(nom)) {
                psPays.setString(1, nom);
                psPays.executeUpdate();
                paysDuFilm.add(nom);
            }
            psFilmPays.setInt(1, idFilm);
            psFilmPays.setString(2, nom);
            psFilmPays.addBatch();
            lotFilmPays++;
        }
    }

    private void insererRoles(int idFilm, ArrayList<LectureXML.Role> roles) throws SQLException {
        HashSet<String> vus = new HashSet<String>();
        for (LectureXML.Role role : roles) {
            String personnage = texte(role.personnage);
            if (personnage == null || personnage.length() > 80 || !personnesInsereesIds.contains(role.id)) {
                rolesIgnores++;
                continue;
            }
            if (!vus.add(role.id + "\0" + personnage)) {
                continue;
            }
            psInterpretation.setInt(1, idFilm);
            psInterpretation.setInt(2, role.id);
            psInterpretation.setString(3, personnage);
            psInterpretation.addBatch();
            lotInterpretations++;
        }
    }

    /** Le XML donne le nom du scenariste, sans identifiant. */
    private void insererScenaristes(int idFilm, ArrayList<String> scenaristes) throws SQLException {
        HashSet<Integer> vus = new HashSet<Integer>();
        for (String scenariste : scenaristes) {
            String nom = texte(scenariste);
            Integer idPersonne = nom == null ? null : idParNom.get(nom);
            if (idPersonne == null || !vus.add(idPersonne)) {
                scenaristesIgnores++;
                continue;
            }
            psScenariste.setInt(1, idFilm);
            psScenariste.setInt(2, idPersonne);
            psScenariste.addBatch();
            lotScenaristes++;
        }
    }

    private void insererAnnonces(int idFilm, ArrayList<String> annonces) throws SQLException {
        HashSet<String> vus = new HashSet<String>();
        for (String annonce : annonces) {
            String lien = texte(annonce);
            if (lien == null || lien.length() > 300 || !vus.add(lien)) {
                continue;
            }
            psAnnonce.setInt(1, idFilm);
            psAnnonce.setString(2, lien);
            psAnnonce.addBatch();
            lotAnnonces++;
        }
    }

    private void insererCopies(int idFilm) throws SQLException {
        int nombre = ThreadLocalRandom.current().nextInt(1, 101);
        for (int i = 1; i <= nombre; i++) {
            psCopie.setString(1, idFilm + "-" + i);
            psCopie.setInt(2, idFilm);
            psCopie.addBatch();
            lotCopies++;
            copiesCreees++;
        }
    }

    /** "3380 Glover Road" devient le numero civique 3380 et la rue Glover Road. */
    private String[] separerAdresse(String adresse) {
        String valeur = texte(adresse);
        if (valeur == null) {
            return null;
        }
        int i = 0;
        while (i < valeur.length() && Character.isDigit(valeur.charAt(i))) {
            i++;
        }
        if (i == 0 || i >= valeur.length()) {
            return null;
        }
        String numero = valeur.substring(0, i);
        String rue = valeur.substring(i).trim();
        if (rue.isEmpty() || numero.length() > 10 || rue.length() > 40) {
            return null;
        }
        return new String[] { numero, rue };
    }

    private void connecter() {
        try {
            connexion = DriverManager.getConnection(URL_BD, UTILISATEUR_BD, MOT_DE_PASSE_BD);
            connexion.setAutoCommit(false);
            preparerRequetes();
            verifierForfaits();
        } catch (SQLException e) {
            connexion = null;
            System.out.println("Connexion impossible : " + e.getMessage());
        }
    }

    private void preparerRequetes() throws SQLException {
        psPersonne = connexion.prepareStatement(
                "INSERT INTO personne (idPersonne, nom, dateNaissance, lieuNaissance, photo, biographie) VALUES (?, ?, ?, ?, ?, ?)");
        psGenre = connexion.prepareStatement("INSERT INTO genre (nom) VALUES (?)");
        psPays = connexion.prepareStatement("INSERT INTO pays (nom) VALUES (?)");
        psFilm = connexion.prepareStatement(
                "INSERT INTO film (idFilm, idRealisateur, titre, anneeSortie, dureeMinutes, langueOriginale, resume, urlAffiche) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
        psFilmGenre = connexion.prepareStatement("INSERT INTO filmGenre (idFilm, nomGenre) VALUES (?, ?)");
        psFilmPays = connexion.prepareStatement("INSERT INTO filmPays (idFilm, nomPays) VALUES (?, ?)");
        psInterpretation = connexion.prepareStatement(
                "INSERT INTO interpretation (idFilm, idPersonne, nomPersonnage) VALUES (?, ?, ?)");
        psScenariste = connexion.prepareStatement(
                "INSERT INTO filmScenariste (idFilm, idPersonne) VALUES (?, ?)");
        psAnnonce = connexion.prepareStatement("INSERT INTO bandeAnnonce (idFilm, lien) VALUES (?, ?)");
        psCopie = connexion.prepareStatement("INSERT INTO copie (codeCopie, idFilm) VALUES (?, ?)");
        psUtilisateur = connexion.prepareStatement(
                "INSERT INTO utilisateur (idUtilisateur, nomFamille, prenom, courriel, telephone, dateNaissance, motDePasse) VALUES (?, ?, ?, ?, ?, ?, ?)");
        psAdresse = connexion.prepareStatement(
                "INSERT INTO adresse (idUtilisateur, numeroCivique, rue, ville, province, codePostal) VALUES (?, ?, ?, ?, ?, ?)");
        psClient = connexion.prepareStatement(
                "INSERT INTO client (idUtilisateur, codeForfait) VALUES (?, ?)");
        psCarte = connexion.prepareStatement(
                "INSERT INTO carteCredit (idUtilisateur, type, numero, dateExpiration, cvv) VALUES (?, ?, ?, ?, ?)");
    }

    private void verifierForfaits() throws SQLException {
        Statement statement = connexion.createStatement();
        ResultSet resultat = statement.executeQuery("SELECT COUNT(*) FROM forfait");
        resultat.next();
        int nombre = resultat.getInt(1);
        resultat.close();
        statement.close();
        if (nombre < 3) {
            System.out.println("Les forfaits D, I et A sont absents. Executez T2 - Tables.sql avant ce programme.");
        }
    }

    private void retenirPersonne(int id, String nom) {
        personnesInserees++;
        personnesInsereesIds.add(id);
        if (!idParNom.containsKey(nom)) {
            idParNom.put(nom, id);
        }
    }

    private void validerFilm() throws SQLException {
        executerSiLot(psFilmGenre, lotFilmGenre);
        executerSiLot(psFilmPays, lotFilmPays);
        executerSiLot(psInterpretation, lotInterpretations);
        executerSiLot(psScenariste, lotScenaristes);
        executerSiLot(psAnnonce, lotAnnonces);
        executerSiLot(psCopie, lotCopies);
        remiseAZeroLotsFilms();
        connexion.commit();
        genresDuFilm.clear();
        paysDuFilm.clear();
    }

    private void oublierReferentielsDuFilm() {
        genresConnus.removeAll(genresDuFilm);
        paysConnus.removeAll(paysDuFilm);
        genresDuFilm.clear();
        paysDuFilm.clear();
    }

    private void remiseAZeroLotsFilms() {
        lotFilmGenre = 0;
        lotFilmPays = 0;
        lotInterpretations = 0;
        lotScenaristes = 0;
        lotAnnonces = 0;
        lotCopies = 0;
    }

    private void viderTamponsFilms() {
        viderTampon(psFilmGenre);
        viderTampon(psFilmPays);
        viderTampon(psInterpretation);
        viderTampon(psScenariste);
        viderTampon(psAnnonce);
        viderTampon(psCopie);
        remiseAZeroLotsFilms();
    }

    private void viderTampon(PreparedStatement statement) {
        if (statement == null) {
            return;
        }
        try {
            statement.clearBatch();
        } catch (SQLException e) {
            System.out.println(e.getMessage());
        }
    }

    private void executerSiLot(PreparedStatement statement, int taille) throws SQLException {
        if (taille > 0) {
            statement.executeBatch();
        }
    }

    private void annuler(SQLException e, String contexte) {
        System.out.println(contexte + " : " + e.getMessage());
        if (connexion == null) {
            return;
        }
        try {
            connexion.rollback();
        } catch (SQLException rollback) {
            System.out.println("Rollback impossible : " + rollback.getMessage());
        }
    }

    private String texte(String valeur) {
        if (valeur == null) {
            return null;
        }
        String net = valeur.trim();
        return net.isEmpty() ? null : net;
    }

    private Date lireDate(String valeur) {
        String net = texte(valeur);
        if (net == null) {
            return null;
        }
        try {
            return Date.valueOf(net);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }
}
