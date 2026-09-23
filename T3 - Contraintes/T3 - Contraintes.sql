-- Webflix, contraintes et procedures (tache 3, cas 1 a 4)
-- A executer apres T2 - Tables.sql.
--
-- Cas 2 (connexion) et cas 3 (consultation) ne modifient pas la base :
-- aucune procedure pour ces cas.
-- Le retard de retour (duree max du forfait) est affiche au cas 8,
-- hors de cette tache. Une location en retard reste donc possible.
--
-- Regles
--   CHECK   mot de passe, chaines vides, type de carte, valeurs des forfaits,
--           date de retour coherente
--   FK      code de forfait (deja creee dans T2 : fk_client_forfait)
--   TRIGGER age minimum, carte non expiree, copie disponible, limite du forfait
--   PROCEDURE p_ajouterClient, p_louerFilm

-- ---------------------------------------------------------------------------
-- Reexecution
-- ---------------------------------------------------------------------------
BEGIN
    FOR c IN (
        SELECT table_name, constraint_name
        FROM user_constraints
        WHERE constraint_name IN (
            'CK_USER_MDP', 'CK_USER_NOM', 'CK_USER_PRENOM', 'CK_USER_COURRIEL',
            'CK_USER_TEL', 'CK_ADR_CIVIQUE', 'CK_ADR_RUE', 'CK_ADR_VILLE',
            'CK_ADR_PROV', 'CK_ADR_CP', 'CK_CARTE_TYPE', 'CK_CARTE_NUMERO',
            'CK_CARTE_CVV', 'CK_FORFAIT_CAS1', 'CK_LOCATION_DATES'
        )
    ) LOOP
        EXECUTE IMMEDIATE
            'ALTER TABLE ' || c.table_name || ' DROP CONSTRAINT ' || c.constraint_name;
    END LOOP;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'CREATE SEQUENCE seq_utilisateur START WITH 1 INCREMENT BY 1 NOCACHE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -955 THEN
            RAISE;
        END IF;
END;
/

-- ---------------------------------------------------------------------------
-- CHECK. Oracle considere '' comme NULL, deja refuse par NOT NULL.
-- LENGTH(TRIM(...)) refuse une chaine composee seulement d'espaces.
-- ---------------------------------------------------------------------------
ALTER TABLE utilisateur ADD CONSTRAINT ck_user_mdp
    CHECK (REGEXP_LIKE(motDePasse, '^[[:alnum:]]{5,}$'));

ALTER TABLE utilisateur ADD CONSTRAINT ck_user_nom
    CHECK (LENGTH(TRIM(nomFamille)) > 0);

ALTER TABLE utilisateur ADD CONSTRAINT ck_user_prenom
    CHECK (LENGTH(TRIM(prenom)) > 0);

ALTER TABLE utilisateur ADD CONSTRAINT ck_user_courriel
    CHECK (LENGTH(TRIM(courriel)) > 0);

ALTER TABLE utilisateur ADD CONSTRAINT ck_user_tel
    CHECK (LENGTH(TRIM(telephone)) > 0);

ALTER TABLE adresse ADD CONSTRAINT ck_adr_civique
    CHECK (LENGTH(TRIM(numeroCivique)) > 0);

ALTER TABLE adresse ADD CONSTRAINT ck_adr_rue
    CHECK (LENGTH(TRIM(rue)) > 0);

ALTER TABLE adresse ADD CONSTRAINT ck_adr_ville
    CHECK (LENGTH(TRIM(ville)) > 0);

ALTER TABLE adresse ADD CONSTRAINT ck_adr_prov
    CHECK (LENGTH(TRIM(province)) > 0);

ALTER TABLE adresse ADD CONSTRAINT ck_adr_cp
    CHECK (LENGTH(TRIM(codePostal)) > 0);

-- Cas 1 : VISA, MasterCard ou Amex.
ALTER TABLE carteCredit ADD CONSTRAINT ck_carte_type
    CHECK (type IN ('VISA', 'MasterCard', 'Amex'));

ALTER TABLE carteCredit ADD CONSTRAINT ck_carte_numero
    CHECK (LENGTH(TRIM(numero)) > 0);

ALTER TABLE carteCredit ADD CONSTRAINT ck_carte_cvv
    CHECK (LENGTH(TRIM(cvv)) > 0);

-- Cas 1 : les trois forfaits, avec duree nulle pour A (illimitee).
ALTER TABLE forfait ADD CONSTRAINT ck_forfait_cas1 CHECK (
       (code = 'D' AND cout = 5  AND locationsMax = 1  AND dureeMaxJours = 10)
    OR (code = 'I' AND cout = 10 AND locationsMax = 5  AND dureeMaxJours = 30)
    OR (code = 'A' AND cout = 15 AND locationsMax = 10 AND dureeMaxJours IS NULL)
);

ALTER TABLE location ADD CONSTRAINT ck_location_dates
    CHECK (dateRetour IS NULL OR dateRetour >= dateLocation);

-- ---------------------------------------------------------------------------
-- TRIGGER. SYSDATE n'est pas permis dans un CHECK.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_client_age_minimum
BEFORE INSERT ON client
FOR EACH ROW
DECLARE
    v_naissance DATE;
BEGIN
    SELECT dateNaissance
      INTO v_naissance
      FROM utilisateur
     WHERE idUtilisateur = :NEW.idUtilisateur;

    IF ADD_MONTHS(v_naissance, 18 * 12) > TRUNC(SYSDATE) THEN
        RAISE_APPLICATION_ERROR(-20001, 'Le client doit avoir au moins 18 ans.');
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_utilisateur_age_client
BEFORE UPDATE OF dateNaissance ON utilisateur
FOR EACH ROW
DECLARE
    v_est_client NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO v_est_client
      FROM client
     WHERE idUtilisateur = :NEW.idUtilisateur;

    IF v_est_client > 0 AND ADD_MONTHS(:NEW.dateNaissance, 18 * 12) > TRUNC(SYSDATE) THEN
        RAISE_APPLICATION_ERROR(-20001, 'Le client doit avoir au moins 18 ans.');
    END IF;
END;
/

-- dateExpiration est le dernier jour du mois d'expiration.
CREATE OR REPLACE TRIGGER trg_carte_non_expiree
BEFORE INSERT OR UPDATE OF dateExpiration ON carteCredit
FOR EACH ROW
BEGIN
    IF :NEW.dateExpiration < TRUNC(SYSDATE) THEN
        RAISE_APPLICATION_ERROR(-20002, 'La carte de credit est expiree.');
    END IF;
END;
/

-- Lecture de location en AFTER STATEMENT : evite ORA-04091 (table mutante).
CREATE OR REPLACE TRIGGER trg_location_regles
FOR INSERT OR UPDATE OF codeCopie, dateRetour, idUtilisateur ON location
COMPOUND TRIGGER
    TYPE t_codes IS TABLE OF VARCHAR2(20);
    TYPE t_clients IS TABLE OF NUMBER;
    g_codes   t_codes := t_codes();
    g_clients t_clients := t_clients();

    AFTER EACH ROW IS
    BEGIN
        IF :NEW.dateRetour IS NULL THEN
            g_codes.EXTEND;
            g_clients.EXTEND;
            g_codes(g_codes.COUNT) := :NEW.codeCopie;
            g_clients(g_clients.COUNT) := :NEW.idUtilisateur;
        END IF;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_nb  NUMBER;
        v_max NUMBER;
    BEGIN
        FOR i IN 1 .. g_codes.COUNT LOOP
            SELECT COUNT(*)
              INTO v_nb
              FROM location
             WHERE codeCopie = g_codes(i)
               AND dateRetour IS NULL;

            IF v_nb > 1 THEN
                RAISE_APPLICATION_ERROR(-20003, 'Cette copie est deja en location.');
            END IF;

            SELECT f.locationsMax
              INTO v_max
              FROM client c
              JOIN forfait f ON f.code = c.codeForfait
             WHERE c.idUtilisateur = g_clients(i);

            SELECT COUNT(*)
              INTO v_nb
              FROM location
             WHERE idUtilisateur = g_clients(i)
               AND dateRetour IS NULL;

            IF v_nb > v_max THEN
                RAISE_APPLICATION_ERROR(
                    -20004,
                    'La limite de locations de votre forfait est atteinte. Retournez un film avant d''en louer un autre.'
                );
            END IF;
        END LOOP;
    END AFTER STATEMENT;
END trg_location_regles;
/

-- ---------------------------------------------------------------------------
-- Procedures. La cle idUtilisateur est produite ici, pas recue en parametre.
-- Le client deja inscrit est designe par son courriel (cas 2).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE p_ajouterClient (
    p_nomFamille     IN utilisateur.nomFamille%TYPE,
    p_prenom         IN utilisateur.prenom%TYPE,
    p_courriel       IN utilisateur.courriel%TYPE,
    p_telephone      IN utilisateur.telephone%TYPE,
    p_dateNaissance  IN utilisateur.dateNaissance%TYPE,
    p_motDePasse     IN utilisateur.motDePasse%TYPE,
    p_numeroCivique  IN adresse.numeroCivique%TYPE,
    p_rue            IN adresse.rue%TYPE,
    p_ville          IN adresse.ville%TYPE,
    p_province       IN adresse.province%TYPE,
    p_codePostal     IN adresse.codePostal%TYPE,
    p_typeCarte      IN carteCredit.type%TYPE,
    p_numeroCarte    IN carteCredit.numero%TYPE,
    p_expMois        IN NUMBER,
    p_expAnnee       IN NUMBER,
    p_cvv            IN carteCredit.cvv%TYPE,
    p_codeForfait    IN client.codeForfait%TYPE
) AS
    v_id          utilisateur.idUtilisateur%TYPE;
    v_expiration  DATE;
    v_nb          NUMBER;
    v_insere      BOOLEAN := FALSE;

    PROCEDURE exiger(p_valeur VARCHAR2, p_libelle VARCHAR2) IS
    BEGIN
        IF p_valeur IS NULL OR LENGTH(TRIM(p_valeur)) = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20010,
                'Le champ ' || p_libelle || ' ne peut pas etre vide.'
            );
        END IF;
    END;
BEGIN
    exiger(p_nomFamille, 'nom de famille');
    exiger(p_prenom, 'prenom');
    exiger(p_courriel, 'courriel');
    exiger(p_telephone, 'telephone');
    exiger(p_motDePasse, 'mot de passe');
    exiger(p_numeroCivique, 'numero civique');
    exiger(p_rue, 'rue');
    exiger(p_ville, 'ville');
    exiger(p_province, 'province');
    exiger(p_codePostal, 'code postal');
    exiger(p_typeCarte, 'type de carte');
    exiger(p_numeroCarte, 'numero de carte');
    exiger(p_cvv, 'CVV');
    exiger(p_codeForfait, 'forfait');

    IF p_dateNaissance IS NULL THEN
        RAISE_APPLICATION_ERROR(-20014, 'La date de naissance ne peut pas etre vide.');
    END IF;

    IF NOT REGEXP_LIKE(p_motDePasse, '^[[:alnum:]]{5,}$') THEN
        RAISE_APPLICATION_ERROR(
            -20009,
            'Le mot de passe doit contenir au moins 5 caracteres alphanumeriques.'
        );
    END IF;

    IF p_typeCarte NOT IN ('VISA', 'MasterCard', 'Amex') THEN
        RAISE_APPLICATION_ERROR(
            -20012,
            'Le type de carte doit etre VISA, MasterCard ou Amex.'
        );
    END IF;

    IF p_codeForfait NOT IN ('D', 'I', 'A') THEN
        RAISE_APPLICATION_ERROR(-20011, 'Le forfait doit etre D, I ou A.');
    END IF;

    IF p_expMois NOT BETWEEN 1 AND 12 OR p_expAnnee IS NULL THEN
        RAISE_APPLICATION_ERROR(-20013, 'La date d''expiration de la carte est invalide.');
    END IF;

    v_expiration := LAST_DAY(TO_DATE(
        TO_CHAR(p_expAnnee, 'FM0000') || LPAD(TO_CHAR(p_expMois), 2, '0'),
        'YYYYMM'
    ));

    LOOP
        v_id := seq_utilisateur.NEXTVAL;
        SELECT COUNT(*) INTO v_nb FROM utilisateur WHERE idUtilisateur = v_id;
        EXIT WHEN v_nb = 0;
    END LOOP;

    SAVEPOINT avant_client;
    v_insere := TRUE;

    INSERT INTO utilisateur (
        idUtilisateur, nomFamille, prenom, courriel, telephone, dateNaissance, motDePasse
    ) VALUES (
        v_id, TRIM(p_nomFamille), TRIM(p_prenom), TRIM(p_courriel), TRIM(p_telephone),
        p_dateNaissance, p_motDePasse
    );

    INSERT INTO adresse (
        idUtilisateur, numeroCivique, rue, ville, province, codePostal
    ) VALUES (
        v_id, TRIM(p_numeroCivique), TRIM(p_rue), TRIM(p_ville), TRIM(p_province), TRIM(p_codePostal)
    );

    INSERT INTO client (idUtilisateur, codeForfait)
    VALUES (v_id, p_codeForfait);

    INSERT INTO carteCredit (idUtilisateur, type, numero, dateExpiration, cvv)
    VALUES (v_id, p_typeCarte, TRIM(p_numeroCarte), v_expiration, TRIM(p_cvv));
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        IF v_insere THEN
            ROLLBACK TO avant_client;
        END IF;
        RAISE_APPLICATION_ERROR(-20008, 'Ce courriel est deja utilise.');
    WHEN OTHERS THEN
        IF v_insere THEN
            ROLLBACK TO avant_client;
        END IF;
        RAISE;
END p_ajouterClient;
/

CREATE OR REPLACE PROCEDURE p_louerFilm (
    p_courriel IN utilisateur.courriel%TYPE,
    p_idFilm   IN film.idFilm%TYPE
) AS
    v_idClient   client.idUtilisateur%TYPE;
    v_codeCopie  copie.codeCopie%TYPE;
    v_nbFilms    NUMBER;
    v_insere     BOOLEAN := FALSE;

    CURSOR c_copies IS
        SELECT c.codeCopie
          FROM copie c
         WHERE c.idFilm = p_idFilm
           AND NOT EXISTS (
               SELECT 1
                 FROM location l
                WHERE l.codeCopie = c.codeCopie
                  AND l.dateRetour IS NULL
           )
         ORDER BY c.codeCopie
           FOR UPDATE OF c.codeCopie;
BEGIN
    BEGIN
        SELECT c.idUtilisateur
          INTO v_idClient
          FROM client c
          JOIN utilisateur u ON u.idUtilisateur = c.idUtilisateur
         WHERE u.courriel = p_courriel;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20005, 'Aucun client ne correspond a ce courriel.');
    END;

    SELECT COUNT(*) INTO v_nbFilms FROM film WHERE idFilm = p_idFilm;
    IF v_nbFilms = 0 THEN
        RAISE_APPLICATION_ERROR(-20006, 'Ce film est introuvable.');
    END IF;

    OPEN c_copies;
    FETCH c_copies INTO v_codeCopie;
    IF c_copies%NOTFOUND THEN
        CLOSE c_copies;
        RAISE_APPLICATION_ERROR(-20007, 'Aucune copie de ce film n''est disponible.');
    END IF;
    CLOSE c_copies;

    SAVEPOINT avant_location;
    v_insere := TRUE;

    INSERT INTO location (idUtilisateur, codeCopie, dateLocation)
    VALUES (v_idClient, v_codeCopie, TRUNC(SYSDATE));
EXCEPTION
    WHEN OTHERS THEN
        IF c_copies%ISOPEN THEN
            CLOSE c_copies;
        END IF;
        IF v_insere THEN
            ROLLBACK TO avant_location;
        END IF;
        RAISE;
END p_louerFilm;
/

-- ---------------------------------------------------------------------------
-- Tests. Les donnees creees ici sont annulees.
-- SET SERVEROUTPUT ON avant d'executer ce script pour voir le resultat.
-- ---------------------------------------------------------------------------
SET SERVEROUTPUT ON

DECLARE
    PROCEDURE attendre(p_code NUMBER, p_libelle VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('ECHEC ' || p_libelle || ' : l''operation a ete acceptee');
    END;

    PROCEDURE ok(p_libelle VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('OK    ' || p_libelle);
    END;
BEGIN
    BEGIN
        INSERT INTO utilisateur (
            idUtilisateur, nomFamille, prenom, courriel, telephone, dateNaissance, motDePasse
        ) VALUES (
            -1, 'Test', 'Un', 'mdp-court@exemple.com', '5140000000', DATE '2000-01-01', 'ab'
        );
        attendre(-2290, 'mot de passe trop court');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -2290 THEN ok('mot de passe trop court');
            ELSE DBMS_OUTPUT.PUT_LINE('ECHEC mot de passe trop court : ' || SQLERRM); END IF;
    END;
    ROLLBACK;

    BEGIN
        p_ajouterClient(
            'Tremblay', 'Zoe', 'zoe.mineure@exemple.com', '5141111111',
            ADD_MONTHS(TRUNC(SYSDATE), -17 * 12), 'abcde',
            '10', 'Rue Principale', 'Montreal', 'QC', 'H2X 1Y4',
            'VISA', '4111111111111111', 12, EXTRACT(YEAR FROM SYSDATE) + 2, '123',
            'D'
        );
        attendre(-20001, 'client mineur');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20001 THEN ok('client mineur');
            ELSE DBMS_OUTPUT.PUT_LINE('ECHEC client mineur : ' || SQLERRM); END IF;
    END;
    ROLLBACK;

    BEGIN
        p_ajouterClient(
            'Tremblay', 'Zoe', 'zoe.carte@exemple.com', '5141111111',
            DATE '1990-01-01', 'abcde',
            '10', 'Rue Principale', 'Montreal', 'QC', 'H2X 1Y4',
            'VISA', '4111111111111111', 1, 2000, '123',
            'D'
        );
        attendre(-20002, 'carte expiree');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20002 THEN ok('carte expiree');
            ELSE DBMS_OUTPUT.PUT_LINE('ECHEC carte expiree : ' || SQLERRM); END IF;
    END;
    ROLLBACK;

    BEGIN
        p_ajouterClient(
            'Tremblay', 'Zoe', 'zoe.visa@exemple.com', '5141111111',
            DATE '1990-01-01', 'abcde',
            '10', 'Rue Principale', 'Montreal', 'QC', 'H2X 1Y4',
            'Visa', '4111111111111111', 12, EXTRACT(YEAR FROM SYSDATE) + 2, '123',
            'D'
        );
        attendre(-20012, 'type Visa');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20012 THEN ok('type Visa refuse, VISA attendu');
            ELSE DBMS_OUTPUT.PUT_LINE('ECHEC type Visa : ' || SQLERRM); END IF;
    END;
    ROLLBACK;

    p_ajouterClient(
        'Tremblay', 'Zoe', 'zoe.ok@exemple.com', '5141111111',
        DATE '1990-01-01', 'abcde',
        '10', 'Rue Principale', 'Montreal', 'QC', 'H2X 1Y4',
        'VISA', '4111111111111111', 12, EXTRACT(YEAR FROM SYSDATE) + 2, '123',
        'D'
    );
    ok('abonnement accepte');

    BEGIN
        p_ajouterClient(
            'Tremblay', 'Zoe', 'zoe.ok@exemple.com', '5141111111',
            DATE '1990-01-01', 'abcde',
            '10', 'Rue Principale', 'Montreal', 'QC', 'H2X 1Y4',
            'VISA', '4111111111111111', 12, EXTRACT(YEAR FROM SYSDATE) + 2, '123',
            'D'
        );
        attendre(-20008, 'courriel double');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20008 THEN ok('courriel double');
            ELSE DBMS_OUTPUT.PUT_LINE('ECHEC courriel double : ' || SQLERRM); END IF;
    END;

    INSERT INTO personne (
        idPersonne, nom, dateNaissance, lieuNaissance, photo, biographie
    ) VALUES (
        -1, 'Real Test', DATE '1970-01-01', 'Montreal', 'http://photo', 'Biographie'
    );
    INSERT INTO film (
        idFilm, idRealisateur, titre, anneeSortie, dureeMinutes, langueOriginale, resume, urlAffiche
    ) VALUES (
        -1, -1, 'Film test', 2000, 90, 'French', 'Resume', 'http://affiche'
    );
    INSERT INTO copie (codeCopie, idFilm) VALUES ('TEST-1', -1);
    INSERT INTO copie (codeCopie, idFilm) VALUES ('TEST-2', -1);

    p_louerFilm('zoe.ok@exemple.com', -1);
    ok('premiere location');

    BEGIN
        p_louerFilm('zoe.ok@exemple.com', -1);
        attendre(-20004, 'limite du forfait D');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20004 THEN ok('limite du forfait D');
            ELSE DBMS_OUTPUT.PUT_LINE('ECHEC limite forfait : ' || SQLERRM); END IF;
    END;

    BEGIN
        p_louerFilm('zoe.ok@exemple.com', -99);
        attendre(-20006, 'film inconnu');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20006 THEN ok('film inconnu');
            ELSE DBMS_OUTPUT.PUT_LINE('ECHEC film inconnu : ' || SQLERRM); END IF;
    END;

    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Tests termines, donnees de test annulees.');
END;
/
