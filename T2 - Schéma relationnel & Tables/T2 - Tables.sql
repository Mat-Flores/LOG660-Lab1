-- Webflix, creation des tables (tache 2)
-- Reprend le schema relationnel. Les contraintes metier (CHECK, triggers,
-- procedures) sont dans T3 - Contraintes.sql.
--
-- ON DELETE CASCADE seulement la ou la ligne fille ne peut pas exister
-- sans son parent : composition (adresse, carte, copie) et liens du film
-- (bande-annonce, genre, pays, scenariste, interpretation).
-- Une location n'est pas supprimee en cascade : c'est un historique.

-- ---------------------------------------------------------------------------
-- Reexecution : retire les tables de ce script si elles existent deja
-- ---------------------------------------------------------------------------
BEGIN
    FOR t IN (
        SELECT table_name
        FROM user_tables
        WHERE table_name IN (
            'LOCATION', 'COPIE', 'INTERPRETATION', 'FILMSCENARISTE',
            'FILMGENRE', 'FILMPAYS', 'BANDEANNONCE', 'FILM',
            'PERSONNE', 'GENRE', 'PAYS', 'CARTECREDIT',
            'CLIENT', 'EMPLOYE', 'ADRESSE', 'UTILISATEUR', 'FORFAIT'
        )
    ) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS';
    END LOOP;

END;
/

-- ---------------------------------------------------------------------------
-- Forfaits du cas 1. dureeMaxJours est nulle pour le forfait illimite (A).
-- ---------------------------------------------------------------------------
CREATE TABLE forfait (
    code            VARCHAR2(1)     NOT NULL,
    cout            NUMBER(5, 2)    NOT NULL,
    locationsMax    NUMBER(2)       NOT NULL,
    dureeMaxJours   NUMBER(4),
    CONSTRAINT pk_forfait PRIMARY KEY (code)
);

-- ---------------------------------------------------------------------------
-- Utilisateurs : parent de la specialisation disjointe et complete
-- ---------------------------------------------------------------------------
CREATE TABLE utilisateur (
    idUtilisateur   NUMBER          NOT NULL,
    nomFamille      VARCHAR2(40)    NOT NULL,
    prenom          VARCHAR2(40)    NOT NULL,
    courriel        VARCHAR2(80)    NOT NULL,
    telephone       VARCHAR2(20)    NOT NULL,
    dateNaissance   DATE            NOT NULL,
    motDePasse      VARCHAR2(50)    NOT NULL,
    CONSTRAINT pk_utilisateur PRIMARY KEY (idUtilisateur),
    CONSTRAINT uq_utilisateur_courriel UNIQUE (courriel)
);

CREATE TABLE adresse (
    idUtilisateur   NUMBER          NOT NULL,
    numeroCivique   VARCHAR2(10)    NOT NULL,
    rue             VARCHAR2(40)    NOT NULL,
    ville           VARCHAR2(40)    NOT NULL,
    province        VARCHAR2(2)     NOT NULL,
    codePostal      VARCHAR2(7)     NOT NULL,
    CONSTRAINT pk_adresse PRIMARY KEY (idUtilisateur),
    CONSTRAINT fk_adresse_utilisateur
        FOREIGN KEY (idUtilisateur) REFERENCES utilisateur (idUtilisateur)
        ON DELETE CASCADE
);

CREATE TABLE client (
    idUtilisateur   NUMBER          NOT NULL,
    codeForfait     VARCHAR2(1)     NOT NULL,
    CONSTRAINT pk_client PRIMARY KEY (idUtilisateur),
    CONSTRAINT fk_client_utilisateur
        FOREIGN KEY (idUtilisateur) REFERENCES utilisateur (idUtilisateur)
        ON DELETE CASCADE,
    CONSTRAINT fk_client_forfait
        FOREIGN KEY (codeForfait) REFERENCES forfait (code)
);

CREATE TABLE carteCredit (
    idUtilisateur   NUMBER          NOT NULL,
    type            VARCHAR2(10)    NOT NULL,
    numero          VARCHAR2(19)    NOT NULL,
    dateExpiration  DATE            NOT NULL,
    cvv             VARCHAR2(4)     NOT NULL,
    CONSTRAINT pk_cartecredit PRIMARY KEY (idUtilisateur),
    CONSTRAINT fk_cartecredit_client
        FOREIGN KEY (idUtilisateur) REFERENCES client (idUtilisateur)
        ON DELETE CASCADE
);

CREATE TABLE employe (
    idUtilisateur   NUMBER          NOT NULL,
    matricule       VARCHAR2(7)     NOT NULL,
    CONSTRAINT pk_employe PRIMARY KEY (idUtilisateur),
    CONSTRAINT fk_employe_utilisateur
        FOREIGN KEY (idUtilisateur) REFERENCES utilisateur (idUtilisateur)
        ON DELETE CASCADE,
    CONSTRAINT uq_employe_matricule UNIQUE (matricule)
);

-- ---------------------------------------------------------------------------
-- Catalogue
-- ---------------------------------------------------------------------------
CREATE TABLE personne (
    idPersonne      NUMBER          NOT NULL,
    nom             VARCHAR2(60)    NOT NULL,
    dateNaissance   DATE            NOT NULL,
    lieuNaissance   VARCHAR2(120)   NOT NULL,
    photo           VARCHAR2(200)   NOT NULL,
    biographie      CLOB            NOT NULL,
    CONSTRAINT pk_personne PRIMARY KEY (idPersonne)
);

CREATE TABLE film (
    idFilm          NUMBER          NOT NULL,
    idRealisateur   NUMBER          NOT NULL,
    titre           VARCHAR2(120)   NOT NULL,
    anneeSortie     NUMBER(4)       NOT NULL,
    dureeMinutes    NUMBER(4)       NOT NULL,
    langueOriginale VARCHAR2(30)    NOT NULL,
    resume          VARCHAR2(1000)  NOT NULL,
    urlAffiche      VARCHAR2(200)   NOT NULL,
    CONSTRAINT pk_film PRIMARY KEY (idFilm),
    CONSTRAINT fk_film_realisateur
        FOREIGN KEY (idRealisateur) REFERENCES personne (idPersonne)
);

CREATE TABLE bandeAnnonce (
    idFilm          NUMBER          NOT NULL,
    lien            VARCHAR2(300)   NOT NULL,
    CONSTRAINT pk_bandeannonce PRIMARY KEY (idFilm, lien),
    CONSTRAINT fk_bandeannonce_film
        FOREIGN KEY (idFilm) REFERENCES film (idFilm)
        ON DELETE CASCADE
);

CREATE TABLE genre (
    nom             VARCHAR2(20)    NOT NULL,
    CONSTRAINT pk_genre PRIMARY KEY (nom)
);

CREATE TABLE pays (
    nom             VARCHAR2(30)    NOT NULL,
    CONSTRAINT pk_pays PRIMARY KEY (nom)
);

CREATE TABLE interpretation (
    idFilm          NUMBER          NOT NULL,
    idPersonne      NUMBER          NOT NULL,
    nomPersonnage   VARCHAR2(80)    NOT NULL,
    CONSTRAINT pk_interpretation PRIMARY KEY (idFilm, idPersonne, nomPersonnage),
    CONSTRAINT fk_interpretation_film
        FOREIGN KEY (idFilm) REFERENCES film (idFilm)
        ON DELETE CASCADE,
    CONSTRAINT fk_interpretation_personne
        FOREIGN KEY (idPersonne) REFERENCES personne (idPersonne)
);

CREATE TABLE filmScenariste (
    idFilm          NUMBER          NOT NULL,
    idPersonne      NUMBER          NOT NULL,
    CONSTRAINT pk_filmscenariste PRIMARY KEY (idFilm, idPersonne),
    CONSTRAINT fk_filmscenariste_film
        FOREIGN KEY (idFilm) REFERENCES film (idFilm)
        ON DELETE CASCADE,
    CONSTRAINT fk_filmscenariste_personne
        FOREIGN KEY (idPersonne) REFERENCES personne (idPersonne)
);

CREATE TABLE filmGenre (
    idFilm          NUMBER          NOT NULL,
    nomGenre        VARCHAR2(20)    NOT NULL,
    CONSTRAINT pk_filmgenre PRIMARY KEY (idFilm, nomGenre),
    CONSTRAINT fk_filmgenre_film
        FOREIGN KEY (idFilm) REFERENCES film (idFilm)
        ON DELETE CASCADE,
    CONSTRAINT fk_filmgenre_genre
        FOREIGN KEY (nomGenre) REFERENCES genre (nom)
);

CREATE TABLE filmPays (
    idFilm          NUMBER          NOT NULL,
    nomPays         VARCHAR2(30)    NOT NULL,
    CONSTRAINT pk_filmpays PRIMARY KEY (idFilm, nomPays),
    CONSTRAINT fk_filmpays_film
        FOREIGN KEY (idFilm) REFERENCES film (idFilm)
        ON DELETE CASCADE,
    CONSTRAINT fk_filmpays_pays
        FOREIGN KEY (nomPays) REFERENCES pays (nom)
);

-- ---------------------------------------------------------------------------
-- Inventaire et locations
-- ---------------------------------------------------------------------------
CREATE TABLE copie (
    codeCopie       VARCHAR2(20)    NOT NULL,
    idFilm          NUMBER          NOT NULL,
    CONSTRAINT pk_copie PRIMARY KEY (codeCopie),
    CONSTRAINT fk_copie_film
        FOREIGN KEY (idFilm) REFERENCES film (idFilm)
        ON DELETE CASCADE
);

CREATE TABLE location (
    idLocation      NUMBER GENERATED BY DEFAULT AS IDENTITY,
    idUtilisateur   NUMBER          NOT NULL,
    codeCopie       VARCHAR2(20)    NOT NULL,
    dateLocation    DATE            NOT NULL,
    dateRetour      DATE,
    CONSTRAINT pk_location PRIMARY KEY (idLocation),
    CONSTRAINT fk_location_client
        FOREIGN KEY (idUtilisateur) REFERENCES client (idUtilisateur),
    CONSTRAINT fk_location_copie
        FOREIGN KEY (codeCopie) REFERENCES copie (codeCopie)
);

-- Trois forfaits du cas 1. La duree du forfait A est illimitee.
INSERT INTO forfait (code, cout, locationsMax, dureeMaxJours) VALUES ('D', 5, 1, 10);
INSERT INTO forfait (code, cout, locationsMax, dureeMaxJours) VALUES ('I', 10, 5, 30);
INSERT INTO forfait (code, cout, locationsMax, dureeMaxJours) VALUES ('A', 15, 10, NULL);

COMMIT;
