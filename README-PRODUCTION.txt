SGS Gestion V9 - PWA + Supabase
================================

Cette version remplace le stockage local par une base Supabase partagée.
Elle ajoute une connexion par rôle, une PWA installable, la photo de l'adhérent
et le certificat médical privé (image, caméra ou PDF).

ORDRE DE MISE EN SERVICE
1. Dans Supabase, ouvrir SQL Editor > New query.
2. Coller tout le contenu de supabase-setup.sql puis cliquer Run.
3. Dans Authentication > Users, créer trois utilisateurs confirmés :
   Propriétaire, Administrateur et Coach.
4. Modifier le bloc commenté à la fin du SQL avec leurs trois e-mails,
   puis exécuter uniquement ce bloc pour attribuer les rôles.
5. Publier tous les fichiers du dossier sur GitHub Pages.
6. Tester connexion, création d'un adhérent, photo, certificat et second appareil.

MISE À JOUR V9.6 SUR UN PROJET EXISTANT
- Exécuter supabase-realtime-concurrency.sql une seule fois dans SQL Editor.
- Publier ensuite index.html, cloud.js et sw.js.
- Les listes se synchronisent automatiquement entre appareils.
- Si deux personnes modifient la même fiche, la seconde sauvegarde est refusée
  et la fiche doit être rouverte afin de préserver la première modification.

MISE À JOUR TARIFS V9.8
- Publier index.html et sw.js ; aucune requête Supabase n'est nécessaire.
- Le tarif dépend désormais des disciplines sélectionnées, sans catégorie automatique.
- MMA Ado est disponible au tarif d'une discipline Ado : 220 euros.
- Les mélanges entre disciplines Ado et Adultes sont refusés.
- L'onglet Info Prix est visible par les trois rôles.
- La réduction famille de 20 euros reste appliquée du 2e au 4e membre.

MISE À JOUR SUPPRESSION V9.9
- Exécuter supabase-delete-members.sql une seule fois dans SQL Editor.
- Publier ensuite index.html, cloud.js et sw.js.
- Le Propriétaire et l'Administrateur peuvent supprimer une fiche après confirmation.
- La suppression globale exige la saisie de SUPPRIMER puis une seconde confirmation.
- Les photos et certificats associés sont également effacés.
- Le Coach ne dispose d'aucun droit de suppression, y compris côté base.

CORRECTION CACHE V9.10
- Publier index.html et sw.js après la V9.9.
- Le numéro de version ajouté à cloud.js force les appareils à charger
  les fonctions de suppression les plus récentes.

CORRECTION SUPPRESSION GLOBALE V9.11
- Réexécuter supabase-delete-members.sql dans SQL Editor.
- La suppression globale utilise désormais une clause WHERE explicite,
  exigée par la protection Safe Update de Supabase.
- Aucun fichier GitHub n'est à remplacer pour cette correction.

SÉCURITÉ
- Ne jamais placer une Secret key ou service_role dans ces fichiers.
- Le certificat médical est inaccessible au Coach.
- Les photos sont accessibles aux trois rôles connectés.
- Les données financières complètes sont refusées au Coach par la base.
- La clé publishable présente dans cloud.js est volontairement publique ;
  la protection repose sur Auth et les règles RLS installées par le SQL.

INSTALLATION PWA
- Android/Chrome : menu > Installer l'application.
- iPhone/Safari : Partager > Sur l'écran d'accueil.
- Ordinateur/Chrome ou Edge : icône Installer dans la barre d'adresse.

LIEN À PARTAGER POUR PROPOSER L'INSTALLATION
https://sgsboxemma.github.io/sgs-gestion/?install=1

Ce lien laisse le choix entre Installer l'application et Continuer sur le web.
Le navigateur affiche toujours sa propre confirmation avant l'installation.

--- Mise à jour V11 ---
- Ajout du moyen de paiement Chèque ANCV avec type obligatoire : Physique ou Dématérialisé.
- Ajout de l'onglet Export pour Propriétaire et Administrateur.
- Exports XLSX dédiés : LABAZ, Pass Sport, Coupon Sport et ANCV.
- Chaque export reprend uniquement le montant réellement payé avec le moyen concerné.
- Export ANCV filtrable : Tous, Physique, Dématérialisé.
- Correction V10.1 conservée : âge exporté sans décimales dans l'export général.
- Aucune migration Supabase requise pour ces changements (paiements stockés en JSON).
