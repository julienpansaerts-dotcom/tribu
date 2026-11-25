# Tribu — cahier des charges

> Application iOS privée de pilotage familial. Version 0.1 du cahier des charges — 25 novembre 2026.

## 1. Vision

Un seul endroit pour tout ce qu'une famille doit savoir et faire ensemble : courses, menus, agenda,
rappels, tâches, dépenses, et surtout les informations pratiques de chacun (tailles, pointures,
allergies…). Tout est partagé en temps réel entre les membres de la tribu, selon leur rôle.

Concept visuel : chaleureux, avec **trois ambiances au choix** dans Réglages (chacun choisit la sienne) :
« La porte du frigo », « L'album du soir » et « Les couleurs de la maison ».
Voir la maquette : https://claude.ai/artifact/PSTtMDCDCteqgZiYp3GfWY

## 2. Utilisateurs, tribu et rôles

- **Tribu** (le « hub famille ») : créée par un premier membre. À la création on renseigne :
  nom de la tribu, pays (Belgique par défaut → fuseau `Europe/Brussels`, devise EUR, jours fériés,
  vacances scolaires de la Fédération Wallonie-Bruxelles), membres de la famille (adultes, enfants), couleurs.
- **Rejoindre** : par code d'invitation à 6 caractères (valable 7 jours) ou lien.
- **Personne ≠ compte** : un enfant de 2 ans a une fiche (tailles, santé) sans avoir de compte.
  Un compte peut être relié à une fiche personne.
- **Rôles dynamiques** : créés dans Réglages. Chaque rôle définit, par module, `aucun`, `lecture`
  ou `écriture`. Rôles fournis par défaut :
  - *Parent* : tout en écriture, gestion des membres et des rôles.
  - *Grand-parent* : Agenda (lecture/écriture), Famille (lecture, enfants uniquement).
  - *Ado* : Courses, Agenda, Rappels, Tâches en écriture ; Dépenses masquées.
- **Éléments privés** : tout élément peut être limité à certaines personnes (`visibleTo`), par
  exemple une idée cadeau cachée à la personne concernée.
- **Face ID** : les rubriques Santé, Papiers d'identité et Dépenses peuvent exiger Face ID à l'ouverture.

## 3. Navigation

Barre d'onglets : **Jour** · **Cuisine** (Courses / Menu / Recettes) · **Agenda** · **Famille** ·
**Modules** (Rappels, Tâches, Activités, Dépenses, Réglages).

## 4. Modules

### 4.1 Jour (écran d'accueil)
- Date et heure en volets basculants (signature visuelle).
- « Prochains départs » : liste chronologique fusionnant agenda, rappels et repas du jour.
- Compteurs : tâches suivies, factures à payer, papiers qui expirent.
- Fil d'activité : « Camille a validé “Acheter du pain” », « Alex a changé la pointure de Léo 27 → 28 ».

### 4.2 Famille — infos de chacun (PRIORITÉ)
- **Tailles et mesures** par personne, entièrement personnalisables, avec modèles prêts à l'emploi :
  - Adultes : haut/pull (XS–XXL + taille EU), chemise (col), t-shirt, pantalon (EU + W/L),
    jean, short, robe/jupe, sous-vêtements, soutien-gorge, chaussettes, pointure (EU, + UK/US optionnel),
    gants, bague, chapeau/tour de tête, manteau.
  - Enfants : taille en cm + âge vêtement (ex. « 104 / 4 ans »), pointure, pyjama, bonnet, combinaison
    de ski, gants, couche (bébé), siège auto (groupe).
  - Champ note libre par taille (« coupe slim », « prendre une taille au-dessus chez Zara »).
  - Historique de chaque taille, mise en avant des changements récents, « prochaine taille à acheter ».
- **Croissance** des enfants : taille, poids, périmètre crânien dans le temps, en graphique.
- **Santé** : groupe sanguin, allergies (affichées en alerte sur la fiche), intolérances, traitements,
  vaccins (avec rappels), médecins.
- **Papiers** : carte d'identité (eID), passeport, Kids-ID, carte SIS/mutuelle… avec date
  d'expiration et rappels à 60, 30 et 7 jours.
- **Contacts utiles** : médecins, pédiatre, école, crèche, urgences, voisins.
- **Liste d'envies / idées cadeaux** par personne (peut être privée).
- **Notes à savoir** (« Léo a peur du noir, veilleuse obligatoire »).

### 4.3 Courses
- Plusieurs listes (Supermarché, Pharmacie, Bricolage…).
- Ajout rapide, dictée, produits « habituels » en un toucher, rangement automatique par rayon.
- Quantités et unités ; fusion des doublons venant des recettes (« 2 + 1 oignons = 3 »), avec
  l'origine affichée (« Risotto · mercredi »).
- Temps réel : on voit qui est au magasin et ce qui est coché.
- Coché → l'article est barré puis glisse vers « Dans le panier ».

### 4.4 Recettes et menu de la semaine
- **Coller un lien** → le serveur lit la page et extrait titre, image, temps, portions,
  ingrédients et étapes (données structurées schema.org/Recipe, puis Open Graph en secours).
  L'image est copiée pour ne pas disparaître si le site change.
- Saisie manuelle et photo d'une page de livre (reconnaissance de texte) en option.
- Fiche détaillée : ingrédients ajustables au nombre de portions, étapes, mode cuisine
  (écran qui reste allumé).
- « Ajouter au menu » → choix du jour et des portions → ingrédients ajoutés à la liste de courses,
  avec la possibilité de décocher ce qu'on a déjà.
- Favoris, étiquettes, suggestion au hasard pour les jours vides.

### 4.5 Agenda
- Agenda partagé de la tribu (source de vérité dans l'app).
- **iCloud** : les événements de la tribu sont copiés dans un calendrier « Tribu » de
  l'iPhone de chacun (visibles dans l'app Calendrier d'Apple), et l'app peut afficher les
  calendriers iCloud personnels en superposition.
- Événements assignés à des personnes (couleur du membre), récurrences, rappels avant.
- Jours fériés belges et vacances scolaires de la Fédération Wallonie-Bruxelles (calendrier réformé :
  congés d'automne et de détente de deux semaines).
- Anniversaires automatiques depuis les fiches Famille.

### 4.6 Rappels (notes avec notification)
- Pour qui (un ou plusieurs membres, ou tous), quoi, quand, plusieurs notifications (« 30 min avant »,
  « à l'heure », « 1 jour avant », personnalisé), récurrence.
- Envoyées par le serveur : elles arrivent même si l'app de l'expéditeur est fermée.
- Le destinataire valide directement depuis la notification (bouton « Fait ») ou dans l'app.
- L'expéditeur voit le suivi : envoyé → vu → validé, et reçoit une notification à la validation.

### 4.7 Tâches et idées (brainstorm)
- Vue liste et vue tableau (À faire / En cours / Fait), ou « idées » libres.
- Chaque élément : description, responsables, échéance, sous-tâches, liens (avec aperçu),
  photos, commentaires, coût estimé et coût réel (relié à Dépenses), votes.
- **Suivi** : par défaut on ne suit rien. On peut suivre une tâche ; on est alors notifié de ses
  modifications, au maximum **une notification toutes les 10 minutes par tâche** (les
  modifications sont regroupées : « 3 modifications sur Rénovation salle de bain »).
  Pas de notification pour ses propres modifications.

### 4.8 Activités
- Idées d'activités avec étiquettes (gratuit, pluie, extérieur, âge, durée, distance), lien, photo, votes.
- « Planifier » → crée l'événement dans l'Agenda.
- Après coup : ajouter des photos souvenirs.

### 4.9 Dépenses (compte commun)
- Encodage d'une facture : fournisseur, montant, catégorie, date, échéance, payée / à payer, qui a payé.
- **Scan** : appareil photo avec détection et recadrage de la feuille ; reconnaissance du texte
  pour proposer montant, date, fournisseur, échéance, IBAN et **communication structurée belge**
  (+++123/4567/89012+++), prête à copier dans l'app bancaire.
- Factures récurrentes (loyer, énergie, abonnements) et rappels d'échéance.
- **Budget mensuel par catégorie** avec progression, et tableau de bord du mois et de l'année.
- Garanties : photo du ticket et rappel avant la fin de la garantie.
- Export CSV.

## 5. Transversal
- Widgets écran d'accueil et écran verrouillé : Jour, Liste de courses.
- Siri / Raccourcis : « Ajoute du lait à la liste », « Qu'est-ce qu'on mange ce soir ? ».
- **Style au choix** parmi les trois ambiances, propre à chaque membre.
- Mode clair / sombre (suit l'iPhone), accessibilité Dynamic Type et VoiceOver.
- Fonctionne hors ligne (synchronisation au retour du réseau).
- Langue : français. Fuseau, devise et jours fériés selon le pays de la tribu.

## 6. Notifications — règles

| Source | Déclencheur | Destinataires | Limite |
|---|---|---|---|
| Rappel | Chaque heure choisie | Destinataires du rappel | — |
| Rappel validé | Validation | Auteur du rappel | — |
| Tâche suivie | Modification | Abonnés sauf l'auteur | 1 / 10 min / tâche, regroupées |
| Papier | J-60, J-30, J-7 | Parents | — |
| Facture | J-3 avant l'échéance | Parents | — |
| Événement | Rappel choisi | Personnes assignées | — |

Réglages par membre : couper un type de notification, heures calmes.

## 7. Architecture technique

- **App** : Swift / SwiftUI, iOS 18 minimum (l'iPhone le plus ancien de la famille est un 14 Pro Max). Projet généré par XcodeGen (`project.yml`).
- **Serveur** : Firebase (région Europe) — Authentication (Se connecter avec Apple), Firestore
  (temps réel + cache hors ligne), Storage (photos, factures), Cloud Functions (import de
  recettes, envoi programmé des notifications, regroupement des notifications de tâches,
  rappels d'échéance), Cloud Messaging → APNs.
- **Sur l'iPhone** : VisionKit (scan), Vision (reconnaissance de texte), EventKit (iCloud),
  WidgetKit, App Intents (Siri), LocalAuthentication (Face ID).
- **Polices** (licence OFL, incluses dans l'app) : Bricolage Grotesque et Caveat (frigo), Newsreader et
  Hanken Grotesk (album), Familjen Grotesk (couleurs).
- **Compilation sans Xcode local** : GitHub Actions sur machine macOS → compilation, tests,
  captures d'écran du simulateur à chaque modification, puis envoi sur TestFlight.

### Modèle de données (Firestore)

```
users/{uid}                      profil, tribus
households/{hid}                 nom, pays, fuseau, devise, communauté scolaire
  members/{uid}                  rôle, couleur, personne liée, réglages notif
  roles/{roleId}                 nom, permissions par module
  invites/{code}                 expiration, rôle attribué
  people/{pid}                   nom, naissance, groupe sanguin, allergies, notes, couleur
    sizes/{id}                   catégorie, valeur, système, note, historique
    measurements/{id}            date, taille, poids, périmètre crânien
    documents/{id}               type, expiration (+ scan)
    health/{id}                  vaccins, traitements, médecins
    wishes/{id}                  idée, lien, prix, visibleTo
  contacts/{id}
  lists/{listId}/items/{id}      nom, quantité, unité, rayon, coché par, recettes d'origine
  recipes/{id}                   url, titre, image, portions, temps, ingrédients, étapes, état d'import
  mealPlans/{année-semaine}      jour → recette + portions
  events/{id}                    titre, début, fin, personnes, récurrence, rappels
  reminders/{id}                 texte, auteur, destinataires, heure, décalages, état par destinataire
  tasks/{id}                     titre, statut, responsables, échéance, coûts, liens, abonnés
    comments/{id}
  activities/{id}                titre, étiquettes, votes, événement planifié
  expenses/{id}                  fournisseur, montant, catégorie, échéance, payée le, scan, garantie
  budgets/{année-mois}           catégorie → plafond
  feed/{id}                      acteur, action, objet, date
  outbox/{id}                    notifications programmées (gérées par le serveur)
```

Règles de sécurité : seul un membre d'une tribu lit ses données ; l'écriture dépend des
permissions de son rôle ; `visibleTo` restreint la lecture.

## 8. Plan de réalisation

| Étape | Contenu |
|---|---|
| 0. Fondations | Dépôt, compilation dans le cloud, trois ambiances, TestFlight, Firebase, connexion Apple, créer / rejoindre une tribu, rôles |
| 1. Essentiel | Famille (tailles en priorité, santé, papiers, Face ID), Courses, écran Jour, fil d'activité |
| 2. Rappels | Rappels avec notifications serveur, validation, suivi |
| 3. Cuisine | Import de recettes, menu de la semaine, lien avec les courses |
| 4. Agenda | Agenda partagé, copie vers iCloud, jours fériés et vacances |
| 5. Tâches | Tâches et idées, commentaires, suivi avec notifications regroupées |
| 6. Dépenses | Factures, scan, budget par catégorie, garanties |
| 7. Finitions | Activités, widgets, Siri, animations signature, polissage |
