# Polypode Data

Fenêtre **« Données des personnages »** pour [Polypode](https://github.com/Baktov/polypode), sous
forme d'addon séparé : les données **durables** de tous vos personnages (niveau, or, métiers,
équipement, sacs et banques), dans l'esprit de DataStore (Altoholic) ou de WoWthing, mais en
restant simple.

Nécessite **Polypode 0.51.1** ou plus récent.

---

## Installation

1. Installer d'abord **Polypode** (dépendance obligatoire).
2. Placer le dossier `Polypode_Data` dans `World of Warcraft/_retail_/Interface/AddOns/`
   (et, pour **WoW Forever**, dans `World of Warcraft/_classic_beta_/Interface/AddOns/`, par
   exemple par une jonction `mklink /J`).
3. Cocher « Polypode Data » dans la liste des AddOns, **sur chaque personnage** : chacun relève
   ses propres données et les envoie aux autres.

---

## Utilisation

Le bouton **Data** (barre de titre de la fenêtre Polypode) ou `/poly data` ouvre une fenêtre
redimensionnable (poignée du coin bas-droit ; Échap ferme) :

- l'en-tête de la liste donne le **nombre de personnages** et l'**or total** ;
- un **tableau sans trait** (colonnes alignées, en-têtes expliqués au survol) liste tous les
  personnages connus, le personnage joué en tête : **Niveau**, **iLvl** (niveau d'objet équipé),
  **Métiers** (icône et niveau des deux métiers principaux), **Or**, **Temps de jeu**, **Vu**
  (« en ligne » en vert, ou quand le personnage a été vu connecté) ;
- **au survol d'un personnage**, le détail : race, classe, spécialisation, faction, zone, niveau
  d'objet, or, temps de jeu, **tous les métiers** (niveau / maximum), **l'équipement** emplacement
  par emplacement (nom en couleur de qualité, niveau d'objet), et le contenu des **sacs**, de la
  **banque** et de la **banque de bataillon** (nombre d'objets, date du relevé) ;
- **clic droit** sur un personnage : « Oublier ce personnage » (personnage supprimé, renommé...).

### Recherche d'objet

Le champ **Rechercher un objet** (en haut à droite) : dès 2 lettres, la liste devient celle des
objets dont le nom contient le texte (sans accents ni majuscules), dans les sacs, les banques et
l'équipement de tous les personnages. Chaque ligne donne le total et, à droite, qui les possède
(« Bataillon » pour la banque de bataillon) ; l'infobulle précise où (sacs, banque, équipé). Les
noms d'objets encore inconnus du jeu sont demandés au serveur, la liste se complète seule.

---

## Fonctionnement

- Chaque personnage relève ses données **2 secondes après un changement** (or, sacs, équipement,
  niveau, zone, métiers...). La **banque** et la **banque de bataillon** ne sont lisibles que
  **banque ouverte** : elles sont relevées à chaque visite, et les dernières connues restent sinon.
- Le **temps de jeu** est demandé au serveur à la connexion, sans l'afficher dans la discussion
  (un `/played` tapé à la main s'affiche normalement).
- Les données sont **sauvegardées** (fichier de compte `PolypodeDataDB`) et **échangées** entre vos
  clients connectés par Polypode : à chaque rencontre, chaque client annonce la version de ses
  données, et l'autre ne demande que ce qui a changé (messages `DATAV`, `DATAREQ`, `DATA`) ; un
  changement part aux clients connectés 10 secondes après (butin ramassé : un seul envoi groupé).
- La banque de bataillon est commune aux personnages d'un même compte Battle.net : la plus
  récente est affichée.
- Sur **WoW Forever**, ce qui n'existe pas (banque de bataillon, spécialisations...) reste vide.

---

## Version

`1.0.0` : première version (tableau des personnages, détail au survol, recherche d'objet, synchro).
