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
 * Insertions Oracle du chargement Webflix, une ligne a la fois.
 * Une erreur n'annule que la ligne en cours. Les lignes deja confirmees restent.
 * PreparedStatement evite les problemes de caracteres reserves et de dates.
 *
 * Une personne ou un film dont un champ obligatoire manque n'est pas insere.
 * Le CVV, absent des XML, est genere. Chaque film insere recoit 1 a 100 copies.
 */
public class EcritureBD {
    // A adapter a l'instance Oracle du cours.
    private static final String URL_BD = "jdbc:oracle:thin:@//localhost:1521/XEPDB1";
    private static final String UTILISATEUR_BD = "LOG660";
    private static final String MOT_DE_PASSE_BD = "LOG660";

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
            psPersonne.setInt(1, id);
            psPersonne.setString(2, nomNet);
            psPersonne.setDate(3, naissance);
            psPersonne.setString(4, lieuNet);
            psPersonne.setString(5, photoNet);
            GestionFlux.fixerTexte(psPersonne, 6, bioNet);
            psPersonne.executeUpdate();
            connexion.commit();
            retenirPersonne(id, nomNet);
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
        } catch (SQLException e) {
            filmsRejetesChamp++;
            annuler(e, "film " + id);
            return;
        }

        insererGenres(id, genres);
        insererPays(id, pays);
        insererRoles(id, roles);
        insererScenaristes(id, scenaristes);
        insererAnnonces(id, annonces);
        insererCopies(id);
        try {
            connexion.commit();
            filmsInseres++;
            genresDuFilm.clear();
            paysDuFilm.clear();
        } catch (SQLException e) {
            filmsRejetesChamp++;
            oublierReferentielsDuFilm();
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
            psUtilisateur.executeUpdate();

            psAdresse.setInt(1, id);
            psAdresse.setString(2, voie[0]);
            psAdresse.setString(3, voie[1]);
            psAdresse.setString(4, villeNet);
            psAdresse.setString(5, provinceNet);
            psAdresse.setString(6, codePostalNet);
            psAdresse.executeUpdate();

            psClient.setInt(1, id);
            psClient.setString(2, forfaitNet);
            psClient.executeUpdate();

            psCarte.setInt(1, id);
            psCarte.setString(2, carteNet);
            psCarte.setString(3, noCarteNet);
            psCarte.setDate(4, expiration);
            psCarte.setString(5, cvv);
            psCarte.executeUpdate();

            connexion.commit();
            clientsInseres++;
        } catch (SQLException e) {
            clientsRejetes++;
            annuler(e, "client " + id);
        }
    }

    /** Plus de lot a envoyer : chaque ligne est deja confirmee. */
    public void terminerLotPersonnes() {
        confirmerReste("personnes");
    }

    public void terminerLotsFilms() {
        confirmerReste("films");
    }

    public void terminerLotClients() {
        confirmerReste("clients");
    }

    public void afficherPersonnes() {
        System.out.println("Personnes lues : " + personnesLues
                + ", inserees : " + personnesInserees
                + ", rejetees (champ obligatoire absent ou erreur SQL) : " + personnesRejetees);
    }

    public void afficherFilms() {
        System.out.println("Films lus : " + filmsLus
                + ", inseres : " + filmsInseres
                + ", rejetes (champ obligatoire absent ou erreur SQL) : " + filmsRejetesChamp
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

    private void insererGenres(int idFilm, ArrayList<String> genres) {
        HashSet<String> vus = new HashSet<String>();
        for (String genre : genres) {
            String nom = texte(genre);
            if (nom == null || nom.length() > 20 || !vus.add(nom)) {
                continue;
            }
            if (genresConnus.add(nom)) {
                try {
                    psGenre.setString(1, nom);
                    psGenre.executeUpdate();
                    genresDuFilm.add(nom);
                } catch (SQLException e) {
                    genresConnus.remove(nom);
                    signaler(e, "genre " + nom);
                    continue;
                }
            }
            try {
                psFilmGenre.setInt(1, idFilm);
                psFilmGenre.setString(2, nom);
                psFilmGenre.executeUpdate();
            } catch (SQLException e) {
                signaler(e, "film " + idFilm + ", genre " + nom);
            }
        }
    }

    private void insererPays(int idFilm, ArrayList<String> pays) {
        HashSet<String> vus = new HashSet<String>();
        for (String paysNom : pays) {
            String nom = texte(paysNom);
            if (nom == null || nom.length() > 30 || !vus.add(nom)) {
                continue;
            }
            if (paysConnus.add(nom)) {
                try {
                    psPays.setString(1, nom);
                    psPays.executeUpdate();
                    paysDuFilm.add(nom);
                } catch (SQLException e) {
                    paysConnus.remove(nom);
                    signaler(e, "pays " + nom);
                    continue;
                }
            }
            try {
                psFilmPays.setInt(1, idFilm);
                psFilmPays.setString(2, nom);
                psFilmPays.executeUpdate();
            } catch (SQLException e) {
                signaler(e, "film " + idFilm + ", pays " + nom);
            }
        }
    }

    private void insererRoles(int idFilm, ArrayList<LectureXML.Role> roles) {
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
            try {
                psInterpretation.setInt(1, idFilm);
                psInterpretation.setInt(2, role.id);
                psInterpretation.setString(3, personnage);
                psInterpretation.executeUpdate();
            } catch (SQLException e) {
                rolesIgnores++;
                signaler(e, "film " + idFilm + ", role " + role.id);
            }
        }
    }

    /** Le XML donne le nom du scenariste, sans identifiant. */
    private void insererScenaristes(int idFilm, ArrayList<String> scenaristes) {
        HashSet<Integer> vus = new HashSet<Integer>();
        for (String scenariste : scenaristes) {
            String nom = texte(scenariste);
            Integer idPersonne = nom == null ? null : idParNom.get(nom);
            if (idPersonne == null || !vus.add(idPersonne)) {
                scenaristesIgnores++;
                continue;
            }
            try {
                psScenariste.setInt(1, idFilm);
                psScenariste.setInt(2, idPersonne);
                psScenariste.executeUpdate();
            } catch (SQLException e) {
                scenaristesIgnores++;
                signaler(e, "film " + idFilm + ", scenariste " + nom);
            }
        }
    }

    private void insererAnnonces(int idFilm, ArrayList<String> annonces) {
        HashSet<String> vus = new HashSet<String>();
        for (String annonce : annonces) {
            String lien = texte(annonce);
            if (lien == null || lien.length() > 300 || !vus.add(lien)) {
                continue;
            }
            try {
                psAnnonce.setInt(1, idFilm);
                psAnnonce.setString(2, lien);
                psAnnonce.executeUpdate();
            } catch (SQLException e) {
                signaler(e, "film " + idFilm + ", annonce");
            }
        }
    }

    private void insererCopies(int idFilm) {
        int nombre = ThreadLocalRandom.current().nextInt(1, 101);
        for (int i = 1; i <= nombre; i++) {
            try {
                psCopie.setString(1, idFilm + "-" + i);
                psCopie.setInt(2, idFilm);
                psCopie.executeUpdate();
                copiesCreees++;
            } catch (SQLException e) {
                signaler(e, "copie " + idFilm + "-" + i);
            }
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

    private void oublierReferentielsDuFilm() {
        genresConnus.removeAll(genresDuFilm);
        paysConnus.removeAll(paysDuFilm);
        genresDuFilm.clear();
        paysDuFilm.clear();
    }

    private void confirmerReste(String contexte) {
        if (connexion == null) {
            return;
        }
        try {
            connexion.commit();
        } catch (SQLException e) {
            annuler(e, contexte);
        }
    }

    private void signaler(SQLException e, String contexte) {
        System.out.println(contexte + " : " + e.getMessage());
    }

    private void annuler(SQLException e, String contexte) {
        signaler(e, contexte);
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
