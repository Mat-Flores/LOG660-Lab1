-- WEBFLIX - TACHE 3 : CONTRAINTES, CAS 1 A 4
-- A executer une fois, apres T2 - Tables.sql et l'import prevu au labo 1.
-- Noms repris du script fourni : Client.codeForfait, Location.codeCopie.
-- Prerequis T2 : champs obligatoires NOT NULL, courriel UNIQUE, cles etrangeres.
-- Forfait.dureeMaxJours doit accepter NULL pour le forfait A.
-- Corriger les donnees existantes si l'ajout d'un CHECK echoue.

-- CAS 1 : ABONNEMENT

-- Les champs textuels obligatoires ne peuvent pas contenir uniquement des espaces.
ALTER TABLE utilisateur ADD CONSTRAINT ck_user_nom
    CHECK (TRIM(nomFamille) IS NOT NULL);
ALTER TABLE utilisateur ADD CONSTRAINT ck_user_prenom
    CHECK (TRIM(prenom) IS NOT NULL);
ALTER TABLE utilisateur ADD CONSTRAINT ck_user_courriel
    CHECK (TRIM(courriel) IS NOT NULL);
ALTER TABLE utilisateur ADD CONSTRAINT ck_user_tel
    CHECK (TRIM(telephone) IS NOT NULL);
    CHECK (REGEXP_LIKE(telephone, '^[0-9]*$'));
ALTER TABLE adresse ADD CONSTRAINT ck_adr_civique
    CHECK (TRIM(numeroCivique) IS NOT NULL);
ALTER TABLE adresse ADD CONSTRAINT ck_adr_rue
    CHECK (TRIM(rue) IS NOT NULL);
ALTER TABLE adresse ADD CONSTRAINT ck_adr_ville
    CHECK (TRIM(ville) IS NOT NULL);
ALTER TABLE adresse ADD CONSTRAINT ck_adr_prov
    CHECK (TRIM(province) IS NOT NULL);
ALTER TABLE adresse ADD CONSTRAINT ck_adr_cp
    CHECK (TRIM(codePostal) IS NOT NULL);
ALTER TABLE carteCredit ADD CONSTRAINT ck_carte_numero
    CHECK (TRIM(numero) IS NOT NULL);
ALTER TABLE carteCredit ADD CONSTRAINT ck_carte_cvv
    CHECK (TRIM(cvv) IS NOT NULL);

-- Interpretation : au moins cinq caracteres, uniquement lettres et chiffres.
ALTER TABLE utilisateur ADD CONSTRAINT ck_user_mdp
    CHECK (motDePasse IS NOT NULL
           AND REGEXP_LIKE(motDePasse, '^[[:alnum:]]{5,}$'));

ALTER TABLE carteCredit ADD CONSTRAINT ck_carte_type
    CHECK (type IS NOT NULL AND type IN ('VISA', 'MasterCard', 'Amex'));

-- Les valeurs des trois forfaits sont celles de l'enonce.
ALTER TABLE forfait ADD CONSTRAINT ck_forfait_cas1 CHECK (
    code IS NOT NULL AND cout IS NOT NULL AND locationsMax IS NOT NULL
    AND (
        (code = 'D' AND cout = 5 AND locationsMax = 1
         AND dureeMaxJours IS NOT NULL AND dureeMaxJours = 10)
        OR
        (code = 'I' AND cout = 10 AND locationsMax = 5
         AND dureeMaxJours IS NOT NULL AND dureeMaxJours = 30)
        OR
        (code = 'A' AND cout = 15 AND locationsMax = 10
         AND dureeMaxJours IS NULL)
    )
);

-- Le client doit avoir au moins 18 ans lors de son inscription.
CREATE OR REPLACE TRIGGER trg_client_age_minimum
BEFORE INSERT OR UPDATE OF idUtilisateur ON client
FOR EACH ROW
DECLARE
    v_naissance utilisateur.dateNaissance%TYPE;
BEGIN
    SELECT dateNaissance INTO v_naissance
    FROM utilisateur WHERE idUtilisateur = :NEW.idUtilisateur;

    IF v_naissance IS NULL
       OR ADD_MONTHS(TRUNC(v_naissance), 216) > TRUNC(SYSDATE) THEN
        RAISE_APPLICATION_ERROR(-20001, 'Le client doit avoir au moins 18 ans.');
    END IF;
END;
/

-- La regle reste valable si la date de naissance est modifiee.
CREATE OR REPLACE TRIGGER trg_utilisateur_age_client
BEFORE UPDATE OF dateNaissance ON utilisateur
FOR EACH ROW
DECLARE
    v_client NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_client
    FROM client WHERE idUtilisateur = :OLD.idUtilisateur;

    IF v_client > 0 AND (
        :NEW.dateNaissance IS NULL
        OR ADD_MONTHS(TRUNC(:NEW.dateNaissance), 216) > TRUNC(SYSDATE)
    ) THEN
        RAISE_APPLICATION_ERROR(-20001, 'Le client doit avoir au moins 18 ans.');
    END IF;
END;
/

-- Une carte est valide jusqu'a la fin de son mois d'expiration.
CREATE OR REPLACE TRIGGER trg_carte_non_expiree
BEFORE INSERT OR UPDATE OF dateExpiration ON carteCredit
FOR EACH ROW
BEGIN
    IF :NEW.dateExpiration IS NULL
       OR TRUNC(:NEW.dateExpiration, 'MM') < TRUNC(SYSDATE, 'MM') THEN
        RAISE_APPLICATION_ERROR(-20002, 'Date d''expiration de carte invalide.');
    END IF;
END;
/

-- CAS 2 : CONNEXION
-- Verification du courriel et du mot de passe par une requete de lecture.
-- Aucune nouvelle contrainte de table, aucune procedure de mise a jour.

-- CAS 3 : CONSULTATION
-- Requetes de lecture uniquement : aucune procedure de mise a jour.

-- CAS 4 : LOCATION

ALTER TABLE location ADD CONSTRAINT ck_location_dates
    CHECK (dateRetour IS NULL OR dateRetour >= dateLocation);

-- Une copie ne peut avoir deux locations en cours ; le quota doit etre respecte.
-- Le trigger compose lit Location apres l'instruction, sans erreur de table mutante.
-- Les verrous sur le client et la copie protegent les locations simultanees.
CREATE OR REPLACE TRIGGER trg_location_regles
FOR INSERT OR UPDATE OF codeCopie, dateRetour, idUtilisateur ON location
COMPOUND TRIGGER
    TYPE t_codes IS TABLE OF copie.codeCopie%TYPE INDEX BY PLS_INTEGER;
    TYPE t_clients IS TABLE OF client.idUtilisateur%TYPE INDEX BY PLS_INTEGER;
    g_codes t_codes;
    g_clients t_clients;
    g_nombre PLS_INTEGER := 0;

    BEFORE EACH ROW IS
        v_client client.idUtilisateur%TYPE;
        v_copie copie.codeCopie%TYPE;
    BEGIN
        IF :NEW.dateRetour IS NULL THEN
            SELECT idUtilisateur INTO v_client
            FROM client WHERE idUtilisateur = :NEW.idUtilisateur FOR UPDATE;

            SELECT codeCopie INTO v_copie
            FROM copie WHERE codeCopie = :NEW.codeCopie FOR UPDATE;

            g_nombre := g_nombre + 1;
            g_clients(g_nombre) := v_client;
            g_codes(g_nombre) := v_copie;
        END IF;
    END BEFORE EACH ROW;

    AFTER STATEMENT IS
        v_nb NUMBER;
        v_max forfait.locationsMax%TYPE;
    BEGIN
        FOR i IN 1 .. g_nombre LOOP
            SELECT COUNT(*) INTO v_nb
            FROM location
            WHERE codeCopie = g_codes(i) AND dateRetour IS NULL;

            IF v_nb > 1 THEN
                RAISE_APPLICATION_ERROR(-20003, 'Cette copie est deja louee.');
            END IF;

            SELECT f.locationsMax INTO v_max
            FROM client c JOIN forfait f ON f.code = c.codeForfait
            WHERE c.idUtilisateur = g_clients(i);

            SELECT COUNT(*) INTO v_nb
            FROM location
            WHERE idUtilisateur = g_clients(i) AND dateRetour IS NULL;

            IF v_nb > v_max THEN
                RAISE_APPLICATION_ERROR(-20004, 'Le quota de locations est depasse.');
            END IF;
        END LOOP;
    END AFTER STATEMENT;
END;
/

-- Duree : date limite = dateLocation + dureeMaxJours (NULL pour A).
-- Un retour tardif reste enregistrable ; le retard est constate au cas 8.

-- PROCEDURES A IMPLEMENTER ET TESTER AU LABO 2 SEULEMENT
-- p_ajouterClient : informations personnelles, adresse, carte et code du forfait.
-- Generer idUtilisateur en interne ; inserer les quatre lignes dans une transaction.
-- p_louerFilm : courriel du client et film choisi.
-- Attribuer une copie disponible ; generer idLocation et enregistrer la location.
-- Afficher des erreurs significatives et annuler toute operation incomplete.

-- TESTS DES CONTRAINTES
-- A executer dans une session de test. Les modifications sont annulees.
-- Les tests utilisent les lignes existantes ; un test sans donnee est signale.
SET SERVEROUTPUT ON

DECLARE
    PROCEDURE tester(p_libelle VARCHAR2, p_sql VARCHAR2, p_erreur NUMBER) IS
        v_code NUMBER;
        v_message VARCHAR2(4000);
        v_lignes NUMBER;
    BEGIN
        SAVEPOINT avant_test;
        BEGIN
            EXECUTE IMMEDIATE p_sql;
            v_lignes := SQL%ROWCOUNT;
            IF v_lignes = 0 THEN
                DBMS_OUTPUT.PUT_LINE('NON TESTE : ' || p_libelle || ' (aucune ligne)');
            ELSIF p_erreur = 0 THEN
                DBMS_OUTPUT.PUT_LINE('OK : ' || p_libelle);
            ELSE
                DBMS_OUTPUT.PUT_LINE('ECHEC : ' || p_libelle || ' accepte');
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                v_code := SQLCODE;
                v_message := SQLERRM;
                IF v_code = p_erreur THEN
                    DBMS_OUTPUT.PUT_LINE('OK : ' || p_libelle);
                ELSE
                    DBMS_OUTPUT.PUT_LINE('ECHEC : ' || p_libelle || ' - ' || v_message);
                END IF;
        END;
        ROLLBACK TO avant_test;
    END;
BEGIN
    tester('Nom compose d''espaces',
        q'[UPDATE utilisateur SET nomFamille = '   ' WHERE idUtilisateur = (SELECT MIN(idUtilisateur) FROM utilisateur)]', -2290);
    tester('Mot de passe trop court',
        q'[UPDATE utilisateur SET motDePasse = 'ab12' WHERE idUtilisateur = (SELECT MIN(idUtilisateur) FROM utilisateur)]', -2290);
    tester('Mot de passe valide',
        q'[UPDATE utilisateur SET motDePasse = 'Ab123' WHERE idUtilisateur = (SELECT MIN(idUtilisateur) FROM utilisateur)]', 0);
    tester('Client mineur',
        q'[UPDATE utilisateur SET dateNaissance = ADD_MONTHS(TRUNC(SYSDATE), -204) WHERE idUtilisateur = (SELECT MIN(idUtilisateur) FROM client)]', -20001);
    tester('Client majeur',
        q'[UPDATE utilisateur SET dateNaissance = ADD_MONTHS(TRUNC(SYSDATE), -240) WHERE idUtilisateur = (SELECT MIN(idUtilisateur) FROM client)]', 0);
    tester('Carte expiree',
        q'[UPDATE carteCredit SET dateExpiration = ADD_MONTHS(TRUNC(SYSDATE, 'MM'), -1) WHERE idUtilisateur = (SELECT MIN(idUtilisateur) FROM carteCredit)]', -20002);
    tester('Carte valide ce mois-ci',
        q'[UPDATE carteCredit SET dateExpiration = TRUNC(SYSDATE, 'MM') WHERE idUtilisateur = (SELECT MIN(idUtilisateur) FROM carteCredit)]', 0);
    tester('Type de carte invalide',
        q'[UPDATE carteCredit SET type = 'Autre' WHERE idUtilisateur = (SELECT MIN(idUtilisateur) FROM carteCredit)]', -2290);
    tester('Duree illimitee interdite pour D',
        q'[UPDATE forfait SET dureeMaxJours = NULL WHERE code = 'D']', -2290);
    tester('Courriel deja utilise',
        q'[UPDATE utilisateur SET courriel = (SELECT courriel FROM utilisateur WHERE idUtilisateur = (SELECT MIN(idUtilisateur) FROM utilisateur)) WHERE idUtilisateur = (SELECT MAX(idUtilisateur) FROM utilisateur) AND idUtilisateur <> (SELECT MIN(idUtilisateur) FROM utilisateur)]', -1);
END;
/

-- Tests de location : un client D de test et deux copies disponibles sont necessaires.
-- Ces tests supposent que T2 autorise les identifiants explicites
-- (pas de colonne GENERATED ALWAYS). Ils sont choisis sous les valeurs existantes.
DECLARE
    v_client NUMBER;
    v_location NUMBER;
    v_copie1 copie.codeCopie%TYPE;
    v_copie2 copie.codeCopie%TYPE;
    v_nb NUMBER;
BEGIN
    SAVEPOINT avant_tests_location;
    SELECT COUNT(*) INTO v_nb FROM forfait WHERE code = 'D';
    IF v_nb = 0 THEN
        DBMS_OUTPUT.PUT_LINE('NON TESTE : locations (forfait D absent)');
        RETURN;
    END IF;

    SELECT MIN(c.codeCopie), MAX(c.codeCopie) INTO v_copie1, v_copie2
    FROM copie c
    WHERE NOT EXISTS (
        SELECT 1 FROM location l
        WHERE l.codeCopie = c.codeCopie AND l.dateRetour IS NULL
    );
    IF v_copie1 IS NULL OR v_copie1 = v_copie2 THEN
        DBMS_OUTPUT.PUT_LINE('NON TESTE : locations (deux copies disponibles requises)');
        RETURN;
    END IF;

    SELECT LEAST(NVL(MIN(idUtilisateur), 0), 0) - 1 INTO v_client FROM utilisateur;
    SELECT LEAST(NVL(MIN(idLocation), 0), 0) - 1 INTO v_location FROM location;

    INSERT INTO utilisateur
        (idUtilisateur, nomFamille, prenom, courriel, telephone, dateNaissance, motDePasse)
    VALUES
        (v_client, 'Test', 'Location', 'test' || ABS(v_client) || '@webflix.test',
         '5140000000', DATE '1990-01-01', 'Ab123');
    INSERT INTO client (idUtilisateur, codeForfait) VALUES (v_client, 'D');

    INSERT INTO location (idLocation, idUtilisateur, codeCopie, dateLocation)
    VALUES (v_location, v_client, v_copie1, TRUNC(SYSDATE));
    DBMS_OUTPUT.PUT_LINE('OK : premiere location');

    BEGIN
        INSERT INTO location (idLocation, idUtilisateur, codeCopie, dateLocation)
        VALUES (v_location - 1, v_client, v_copie1, TRUNC(SYSDATE));
        DBMS_OUTPUT.PUT_LINE('ECHEC : copie deja louee acceptee');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20003 THEN DBMS_OUTPUT.PUT_LINE('OK : copie deja louee refusee');
            ELSE DBMS_OUTPUT.PUT_LINE('ECHEC : disponibilite - ' || SQLERRM); END IF;
    END;

    BEGIN
        INSERT INTO location (idLocation, idUtilisateur, codeCopie, dateLocation)
        VALUES (v_location - 2, v_client, v_copie2, TRUNC(SYSDATE));
        DBMS_OUTPUT.PUT_LINE('ECHEC : depassement du quota accepte');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20004 THEN DBMS_OUTPUT.PUT_LINE('OK : depassement du quota refuse');
            ELSE DBMS_OUTPUT.PUT_LINE('ECHEC : quota - ' || SQLERRM); END IF;
    END;
    ROLLBACK TO avant_tests_location;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO avant_tests_location;
        DBMS_OUTPUT.PUT_LINE('ECHEC : preparation des tests de location - ' || SQLERRM);
END;
/

-- Script relu, non execute sur Oracle ici. Conserver les sorties des tests.
