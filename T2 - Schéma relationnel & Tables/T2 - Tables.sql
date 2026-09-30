CREATE TABLE forfait (
    code            VARCHAR2(1)     NOT NULL,
    cout            NUMBER(5, 2)    NOT NULL,
    locationsMax    NUMBER(2)       NOT NULL,
    dureeMaxJours   NUMBER(4),
    CONSTRAINT pk_forfait PRIMARY KEY (code)
);

CREATE TABLE utilisateur (
    idUtilisateur   NUMBER          NOT NULL,
    nomFamille      VARCHAR2(40),
    prenom          VARCHAR2(40),
    courriel        VARCHAR2(80),
    telephone       VARCHAR2(20),
    dateNaissance   DATE,
    motDePasse      VARCHAR2(50),
    CONSTRAINT pk_utilisateur PRIMARY KEY (idUtilisateur),
    CONSTRAINT uq_utilisateur_courriel UNIQUE (courriel)
);

CREATE TABLE adresse (
    idUtilisateur   NUMBER          NOT NULL,
    numeroCivique   VARCHAR2(10),
    rue             VARCHAR2(40),
    ville           VARCHAR2(40),
    province        VARCHAR2(2),
    codePostal      VARCHAR2(7),
    CONSTRAINT pk_adresse PRIMARY KEY (idUtilisateur),
    CONSTRAINT fk_adresse_utilisateur
        FOREIGN KEY (idUtilisateur) REFERENCES utilisateur (idUtilisateur)
        ON DELETE CASCADE
);

CREATE TABLE client (
    idUtilisateur   NUMBER          NOT NULL,
    codeForfait     VARCHAR2(1),
    CONSTRAINT pk_client PRIMARY KEY (idUtilisateur),
    CONSTRAINT fk_client_utilisateur
        FOREIGN KEY (idUtilisateur) REFERENCES utilisateur (idUtilisateur)
        ON DELETE CASCADE,
    CONSTRAINT fk_client_forfait
        FOREIGN KEY (codeForfait) REFERENCES forfait (code)
);

CREATE TABLE carteCredit (
    idUtilisateur   NUMBER          NOT NULL,
    type            VARCHAR2(10),
    numero          VARCHAR2(19),
    dateExpiration  DATE,
    cvv             VARCHAR2(4),
    CONSTRAINT pk_cartecredit PRIMARY KEY (idUtilisateur),
    CONSTRAINT fk_cartecredit_client
        FOREIGN KEY (idUtilisateur) REFERENCES client (idUtilisateur)
        ON DELETE CASCADE
);

CREATE TABLE employe (
    idUtilisateur   NUMBER          NOT NULL,
    matricule       VARCHAR2(7),
    CONSTRAINT pk_employe PRIMARY KEY (idUtilisateur),
    CONSTRAINT fk_employe_utilisateur
        FOREIGN KEY (idUtilisateur) REFERENCES utilisateur (idUtilisateur)
        ON DELETE CASCADE,
    CONSTRAINT uq_employe_matricule UNIQUE (matricule)
);

CREATE TABLE personne (
    idPersonne      NUMBER          NOT NULL,
    nom             VARCHAR2(60),
    dateNaissance   DATE,
    lieuNaissance   VARCHAR2(120),
    photo           VARCHAR2(200),
    biographie      CLOB,
    CONSTRAINT pk_personne PRIMARY KEY (idPersonne)
);

CREATE TABLE film (
    idFilm          NUMBER          NOT NULL,
    idRealisateur   NUMBER,
    titre           VARCHAR2(120),
    anneeSortie     NUMBER(4),
    dureeMinutes    NUMBER(4),
    langueOriginale VARCHAR2(30),
    resume          VARCHAR2(1000),
    urlAffiche      VARCHAR2(200),
    CONSTRAINT pk_film PRIMARY KEY (idFilm),
    CONSTRAINT fk_film_realisateur
        FOREIGN KEY (idRealisateur) REFERENCES personne (idPersonne)
);

CREATE TABLE bandeAnnonce (
    idFilm          NUMBER          NOT NULL,
    lien            VARCHAR2(300),
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
    nomPersonnage   VARCHAR2(80),
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

INSERT INTO forfait (code, cout, locationsMax, dureeMaxJours)
VALUES ('D', 5, 1, 10);

INSERT INTO forfait (code, cout, locationsMax, dureeMaxJours)
VALUES ('I', 10, 5, 30);

INSERT INTO forfait (code, cout, locationsMax, dureeMaxJours)
VALUES ('A', 15, 10, NULL);

COMMIT;
