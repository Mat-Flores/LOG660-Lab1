-- ######### CAS 1 : ABONNEMENT #########

-- Les champs textuels obligatoires ne peuvent pas contenir uniquement des espaces.
ALTER TABLE utilisateur ADD CONSTRAINT ck_user_nom
    CHECK (TRIM(nomFamille) IS NOT NULL);
ALTER TABLE utilisateur ADD CONSTRAINT ck_user_prenom
    CHECK (TRIM(prenom) IS NOT NULL);
ALTER TABLE utilisateur ADD CONSTRAINT ck_user_courriel
    CHECK (TRIM(courriel) IS NOT NULL);
ALTER TABLE utilisateur ADD CONSTRAINT ck_user_tel
    CHECK (TRIM(telephone) IS NOT NULL);
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
CREATE OR REPLACE TRIGGER trg_age_client
BEFORE INSERT OR UPDATE OF idUtilisateur ON client
FOR EACH ROW
DECLARE
    v_naissance Utilisateur.dateNaissance%TYPE;
BEGIN
    SELECT dateNaissance INTO v_naissance
    FROM utilisateur
    WHERE idUtilisateur = :NEW.idUtilisateur;

    IF v_naissance IS NULL
       OR TRUNC(v_naissance) > ADD_MONTHS(TRUNC(SYSDATE), -216) THEN
        RAISE_APPLICATION_ERROR(-20001, 'Le client doit avoir au moins 18 ans.');
    END IF;
END;
/

-- La regle reste valable si la date de naissance est modifiee.
CREATE OR REPLACE TRIGGER trg_modification_naissance
BEFORE UPDATE OF dateNaissance ON utilisateur
FOR EACH ROW
DECLARE
    v_client NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_client
    FROM client WHERE idUtilisateur = :OLD.idUtilisateur;

    IF v_client > 0 AND (
        :NEW.dateNaissance IS NULL
        OR TRUNC(:NEW.dateNaissance) > ADD_MONTHS(TRUNC(SYSDATE), -216)
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

-- ######### CAS 2 : CONNEXION ############
-- Verification du courriel et du mot de passe par une requete de lecture.
-- Aucune nouvelle contrainte de table, aucune procedure de mise a jour.

-- ######### CAS 3 : CONSULTATION #########
-- Requetes de lecture uniquement : aucune procedure de mise a jour.

-- ######### CAS 4 : LOCATION #############

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