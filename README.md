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
  par emplacement (nom en couleur de qualité, niveau d'objet, **niveau d'amélioration** —
  « Champion 4/6 » —, **enchantement** en vert et **gemmes** sous la pièce), et le contenu des **sacs**, de la
  **banque**, de la **banque de bataillon** et de la **banque de guilde** du personnage (nombre
  d'objets, or de la guilde, date du relevé) ;
- **clic gauche** sur un personnage : sa **fiche** (le même détail) reste affichée dans un cadre
  **déplaçable** (glisser) ; on peut en ouvrir plusieurs pour comparer ; la **croix** en haut à
  droite la ferme. Un **clic** (gauche ou droit) sur une ligne marquée « » » affiche son détail :
  contenu des **sacs**, de la **banque**, de la **banque de bataillon** ou de la **banque de
  guilde** (une fiche de plus, un
  objet par ligne avec son nombre), ou l'**infobulle de l'objet** équipé (celle de WoW, épinglée, avec son
  enchantement, ses gemmes et ses bonus exacts).
  Dans une fiche de sac, un clic sur un objet affiche aussi son infobulle ;
- **clic droit** sur un personnage : « Oublier ce personnage » (personnage supprimé, renommé...).

### Dépôts possibles

Le bouton **Dépôts** (à gauche de la barre de titre) ouvre une fiche (déplaçable, croix pour la
fermer) qui liste, **pour chaque personnage**, les objets de ses **sacs** qui existent **déjà**
dans l'une de ses trois banques, et qui pourraient donc y être rangés :

- **Banque** (la sienne) ;
- **Banque de bataillon** (celle de son compte Battle.net) ;
- **Banque de guilde** (celle de sa guilde).

Chaque objet donne le nombre dans les sacs et, en gris, celui déjà en banque ; un clic affiche
son infobulle. Les banques doivent avoir été relevées (ouvertes une fois). La fiche se met à jour
toute seule (butin, dépôt, données reçues) ; le bouton la referme.

**Ranger** (en haut de la fiche) : avec la **banque du personnage** ouverte, dépose dans cette
banque les objets des sacs qui s'y trouvent **déjà**, et seulement eux :

- sur la **pile existante** (complétée jusqu'au maximum), sinon dans un emplacement libre du
  **même onglet**, sinon ailleurs dans la banque ;
- un compteur suit l'avancement (« Rangement : 5 sur 30 ») jusqu'à « Les 30 objets ont été
  déposés dans la banque » (une pile des sacs compte pour un objet) ;
- s'il n'y a plus de place, le rangement s'arrête et le signale ; il s'arrête aussi si la
  banque se ferme ; pendant le rangement, le bouton devient **Arrêter**.

Le bouton est grisé si la banque du personnage n'est pas ouverte, ou si une autre banque l'est
aussi (onglet bataillon affiché, banque de guilde), ou si seule la banque de bataillon est
ouverte (coffre de bataillon, accès à distance) : l'infobulle l'explique. Avec un addon de sacs
qui remplace la fenêtre de banque (Baganator...), l'onglet affiché n'est pas lisible : le bouton
reste actif chez un banquier, et le rangement va toujours dans la banque du personnage. Banque de bataillon et
banque de guilde : à venir.

### Recherche d'objet

Le champ **Rechercher un objet** (en haut à droite) : dès 2 lettres, la liste devient celle des
objets dont le nom contient le texte (sans accents ni majuscules), dans les sacs, les banques et
l'équipement de tous les personnages. Chaque ligne donne le total et, à droite, qui les possède
(« Bataillon » pour la banque de bataillon, « Guilde … » pour une banque de guilde) ; l'infobulle précise où (sacs, banque, équipé). Les
noms d'objets encore inconnus du jeu sont demandés au serveur, la liste se complète seule.

---

## Fonctionnement

- Chaque personnage relève ses données **2 secondes après un changement** (or, sacs, équipement,
  niveau, zone, métiers...) ; le dernier relevé est celui qui reste sauvegardé à la déconnexion
  (le jeu vide déjà sacs, équipement et or à ce moment-là). La **banque** et la **banque de bataillon** ne sont lisibles que
  **banque ouverte** : elles sont relevées à chaque visite, et les dernières connues restent sinon.
- Le **temps de jeu** est demandé au serveur à la connexion, sans l'afficher dans la discussion
  (un `/played` tapé à la main s'affiche normalement).
- Les données sont **sauvegardées** (fichier de compte `PolypodeDataDB`) et **échangées** entre vos
  clients connectés par Polypode : à chaque rencontre, chaque client annonce la version de ses
  données, et l'autre ne demande que ce qui a changé (messages `DATAV`, `DATAREQ`, `DATA`) ; un
  changement part aux clients connectés 10 secondes après (butin ramassé : un seul envoi groupé).
- La banque de bataillon est commune aux personnages d'un même compte Battle.net : la plus
  récente est affichée.
- **Banque de guilde** : relevée quand un de vos personnages l'ouvre (tous les onglets qu'il peut
  voir sont demandés au serveur à l'ouverture) ; la plus récente de chaque guilde est affichée
  dans la fiche de chaque personnage de cette guilde, et comptée dans la recherche.
- Sur **WoW Forever**, ce qui n'existe pas (banque de bataillon, spécialisations...) reste vide.

---

## Version

`1.5.1` : « Ranger » grisé quand seule la banque de bataillon est ouverte (coffre de bataillon, accès à distance).
`1.5.0` : bouton « Ranger » (fiche Dépôts) : dépôt automatique dans la banque du personnage des objets qui y sont déjà.
`1.4.1` : correctif : la déconnexion n'efface plus l'or, les métiers, l'équipement et les sacs sauvegardés (relevé fait alors que le jeu les avait déjà vidés).
`1.4.0` : bouton « Dépôts » : objets des sacs déjà présents dans une banque, par personnage.
`1.3.0` : banque de guilde (fiche, détail, recherche).
`1.2.0` : équipement relevé avec son lien complet : enchantement, gemmes et niveau d'amélioration affichés.
`1.1.1` : fiches fermées par une croix, détail ouvert par un clic.
`1.1.0` : fiches épinglées (clic gauche sur un personnage), détail des sacs et banques, infobulle des objets.
`1.0.0` : première version (tableau des personnages, détail au survol, recherche d'objet, synchro).
