# Polypode Data

Fenêtre **« Données des personnages »** pour [Polypode](https://github.com/Baktov/polypode), sous
forme d'addon séparé : les données **durables** de tous vos personnages (niveau, or, métiers,
équipement, sacs et banques), dans l'esprit de DataStore (Altoholic) ou de WoWthing, mais en
restant simple.

Nécessite **Polypode 0.51.1** ou plus récent.

---

## Installation

1. Installer d'abord **Polypode** (dépendance obligatoire ; affichage en icônes : Polypode 0.56 ou plus).
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
  objet par ligne avec son nombre ; dans la fiche du personnage, chaque sac ou banque tient sur une
  ligne, la guilde, l'or et la date du relevé sont dans son infobulle), ou l'**infobulle de l'objet** équipé (celle de WoW, épinglée, avec son
  enchantement, ses gemmes et ses bonus exacts).
  Dans une fiche de sac, un clic sur un objet affiche aussi son infobulle ;
- **clic droit** sur un personnage : « Oublier ce personnage » (personnage supprimé, renommé...).

### Sacs et banques du personnage joué

À droite du bouton **Dépôts**, quatre icônes : **sac** (sacs), **pièces d'or** (banque du
personnage), **emblème du bataillon** (banque de bataillon du compte) et **coffre de guilde**
(banque de guilde de sa guilde). Au survol : le nombre
d'objets, le nombre d'objets différents (et l'or de la banque de guilde) et la date du relevé ;
au clic : la fiche du contenu, la même que depuis le détail du personnage. Une banque jamais
ouverte avec ce personnage (ou un personnage de la guilde) n'est pas encore relevée : l'infobulle
l'indique.

**Clic droit** sur une icône : **Remettre à zéro** efface ce relevé (sur ce client). Les sacs sont
relus aussitôt ; une banque doit être **rouverte** pour être relevée de nouveau (le message le rappelle).

La banque de bataillon appartient à un **compte Battle.net**, la banque de guilde à une **guilde** :
quel que soit le personnage qui l'ouvre, Polypode Data n'en garde **qu'un relevé** (le plus récent
remplace les autres, jamais cumulés).

### Rechercher une recette

À droite du champ **Rechercher un objet** (tous deux à droite du titre), un second champ **Rechercher une recette** : dès 2 lettres,
la liste devient celle des recettes apprises (de tous les personnages en mémoire) dont le nom
contient le texte, sans tenir compte des accents ni des majuscules. Chaque recette indique
combien de personnages la connaissent et lesquels ; au survol, chacun avec l'extension de la
recette ; un clic ouvre l'infobulle de la recette. Une seule recherche à la fois : taper dans un
champ vide l'autre. Seules les recettes déjà relevées sont trouvées (fenêtre de chaque métier
ouverte une fois avec chaque personnage).

### Métiers d'un personnage

Dans la fiche épinglée d'un personnage, **chaque métier est cliquable** (y compris celui de la
colonne de droite) : il ouvre une fiche avec

1. les **objets de métier** équipés (outil, accessoires), avec leur infobulle au clic ;
2. les **recettes apprises**, regroupées **par extension** (« Khaz Algar », « Îles aux Dragons »...,
   la plus récente en tête), chaque extension **repliable / dépliable** d'un clic (repliées par
   défaut) ; un clic sur une recette ouvre son infobulle.

WoW ne donne les recettes que **fenêtre du métier ouverte** : ouvrez une fois chaque métier avec
chaque personnage pour les relever (seuls vos propres métiers sont relevés, pas le lien de recettes
d'un autre joueur ni une commande d'artisanat). Les objets de métier sont relevés avec
l'équipement (reconnectez une fois le personnage après cette mise à jour). Comme le reste, ces
données sont partagées avec vos autres clients connectés.

### Dépôts possibles

Le bouton **Dépôts** (barre de titre, à droite du bouton **Options**) ouvre une fiche (déplaçable, croix pour la
fermer) qui liste, **pour chaque personnage**, les objets de ses **sacs** qui existent **déjà**
dans l'une de ses trois banques, et qui pourraient donc y être rangés :

- **Banque** (la sienne) ;
- **Banque de bataillon** (celle de son compte Battle.net) ;
- **Banque de guilde** (celle de sa guilde).

Chaque objet donne le nombre dans les sacs et, en gris, celui déjà en banque ; un clic affiche
son infobulle. Les banques doivent avoir été relevées (ouvertes une fois). La fiche se met à jour
toute seule (butin, dépôt, données reçues) ; le bouton la referme.

**Ranger** (en haut de la fiche, et aussi dans la barre de titre de la fenêtre, entre **Dépôts** et
l'icône du sac : même bouton, même fonction ; ou **Maj + clic droit** sur le bouton **Data** de la
fenêtre Polypode ou de la barre flottante, dont le simple clic droit ouvre une petite fenêtre
d'options) : dépose les objets des sacs qui se trouvent **déjà** dans une
banque ouverte, et seulement eux :

- destination : la **banque du personnage** si l'objet y est, sinon la **banque de bataillon**
  s'il y est (et qu'elle l'accepte : pas d'objet lié au personnage) ; un objet absent des
  banques ouvertes ne bouge pas ;
- sur la **pile existante** (complétée jusqu'au maximum), sinon dans un emplacement libre du
  **même onglet**, sinon ailleurs dans cette banque ;
- un compteur suit l'avancement (« Rangement : 5 sur 30 ») jusqu'à « Les 30 objets ont été
  déposés dans la banque » (une pile des sacs compte pour un objet) ;
- un objet **unique** (« Unique », « Unique (n) ») que la banque de bataillon ou de guilde contient
  déjà au maximum permis reste dans les sacs, sans tentative de dépôt (le jeu le refuserait :
  ces banques comptent à part), et c'est signalé à la fin ;
- un objet dont le jeu **refuse** le dépôt (« Vous ne pouvez pas emporter plus de ces objets »...)
  n'est pas retenté : il reste dans les sacs, le rangement continue avec les suivants, et à la
  fin un message dans **votre** fenêtre de discussion (visible de vous seul) liste les objets
  refusés, avec leur lien ;
- s'il n'y a plus de place pour un objet, il reste dans les sacs (les suivants peuvent encore
  compléter une pile existante) et c'est signalé à la fin ; le rangement s'arrête si la banque
  se ferme ; pendant le rangement, le bouton devient **Arrêter**.

**Banque de guilde** : même fonctionnement, dans les seuls onglets où vous avez le **droit de
déposer** (un objet présent dans un onglet sans ce droit va dans un autre onglet autorisé).
Le jeu ne tient à jour que l'onglet affiché : avant de déposer dans un onglet, Polypode Data
l'affiche et attend que le serveur en renvoie le contenu, puis attend sa réponse après chaque
dépôt. C'est plus lent (environ une seconde par objet), et l'onglet affiché change pendant le
rangement.

Banques ouvertes :

- **chez un banquier** (fenêtre de Blizzard ou addon de sacs comme Baganator) : les deux banques,
  quel que soit l'onglet affiché (banque du personnage en priorité) ;
- **banque de bataillon seule** (coffre de bataillon, accès à distance) : le bataillon ;
- **banque de guilde** : la guilde.

Le bouton est grisé si aucune n'est ouverte, si la banque de guilde l'est en même temps qu'une
autre (une seule banque ouverte), ou si vous n'avez le droit de déposer dans aucun onglet de la
banque de guilde : l'infobulle l'explique.

### Recherche d'objet

Le champ **Rechercher un objet** (en haut à droite) : dès 2 lettres, la liste devient celle des
objets dont le nom contient le texte (sans accents ni majuscules), dans les sacs, les banques et
l'équipement de tous les personnages. Chaque ligne donne le total et, à droite, qui les possède
(« Bataillon » pour la banque de bataillon, « Guilde … » pour une banque de guilde) ; l'infobulle précise où (sacs, banque, équipé). Les
noms d'objets encore inconnus du jeu sont demandés au serveur, la liste se complète seule.

### Options

Options → AddOns → Polypode → **Data**, ou bouton **Options** (le plus à gauche de la barre de titre de
la fenêtre, qui se ferme pour laisser voir le panneau), ou **clic droit** sur le bouton **Data** (fenêtre
Polypode ou barre flottante) : petite fenêtre d'options à côté du bouton, avec un bouton **Toutes les
options** (nécessite Polypode 0.57 ; sinon le panneau d'options) :

| Option | Défaut | Effet |
|---|---|---|
| Contenu des sacs et banques | Liste | Affichage du contenu détaillé d'un sac ou d'une banque (clic sur sa ligne dans la fiche d'un personnage, ou sur une icône de l'en-tête) : **Liste** (une ligne par objet, avec son nom et son nombre) ou **Icônes** (grille d'icônes comme les sacs de WoW : nombre sur l'icône, bordure de la couleur de qualité, nom et détail dans l'infobulle, clic = infobulle épinglée). Réglage commun à tous les personnages |

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

`1.16.1` : notions de clic en bleu dans les infobulles et la description de l'option (Polypode 0.60).
`1.16.0` : clic droit sur le bouton « Data » : petite fenêtre d'options à côté du bouton (au lieu du panneau de WoW). Nécessite Polypode 0.57.
`1.15.2` : clic droit sur le bouton « Data » (fenêtre Polypode et barre flottante) : options, comme les autres modules ; « Ranger » passe à Maj + clic droit.
`1.15.1` : bouton « Options » à gauche de la barre de titre (Options → AddOns → Polypode → Data), comme dans Polypode et Suivi.
`1.15.0` : option « Contenu des sacs et banques » (Options → AddOns → Polypode → Data) : contenu détaillé en liste ou en icônes comme les sacs de WoW. Nécessite Polypode 0.56 pour les icônes.
`1.14.5` : fiche d'un personnage : chaque sac ou banque sur une seule ligne, la guilde, l'or et la date du relevé passent dans l'infobulle de la ligne (avec « Clic : contenu détaillé »).
`1.14.4` : correctif « Ranger » : un dépôt refusé par le serveur (accepté d'abord par le jeu, puis l'objet revient dans le sac, ex. hachette de récolte en banque de bataillon) était retenté sans fin, message d'erreur en boucle. L'objet est maintenant laissé dans les sacs sans nouvelle tentative, et les objets refusés sont listés dans le chat (message local) à la fin.
`1.14.3` : « Ranger » : un objet unique déjà présent au maximum permis dans la banque de bataillon ou de guilde reste dans les sacs (plus de dépôt refusé par le jeu, « vous ne pouvez pas en avoir plus ») ; signalé dans le bilan.
`1.14.2` : détail d'un personnage : chaque banque sur deux lignes (nom et nombre d'objets, puis en gris la guilde, l'or et la date du relevé), lisibles sans être tronquées dans la fiche.
`1.14.1` : correctif : l'or, le niveau d'objet et la guilde d'un personnage pouvaient être effacés à la déconnexion (relevé fait juste avant la sortie du monde, quand le jeu les a déjà vidés). Un relevé d'identité dont le niveau d'objet tombe à 0 est ignoré ; la guilde connue est gardée tant que le serveur n'a pas renvoyé son nom.
`1.14.0` : tri du tableau par clic sur un en-tête (Personnage, Niveau, iLvl, Métiers, Or, Hauts faits, Temps de jeu, Vu) ; clic suivant : ordre inverse ; tri gardé.
`1.13.5` : deux colonnes de métiers (une par métier principal), toutes deux alignées à gauche.
`1.13.4` : colonne Métiers alignée à gauche (icônes les unes sous les autres).
`1.13.3` : correctif : l'équipement, les sacs, les métiers et l'or d'un personnage pouvaient être effacés à la déconnexion (relevé fait à la fermeture de la fenêtre de métier, quand le jeu a déjà vidé ces données). Aucun relevé pendant la sortie du monde, et un relevé vide ne remplace plus un relevé plein.
`1.13.2` : guilde du personnage entre parenthèses à droite de son nom dans le tableau.
`1.13.1` : colonne « Hauts faits » : points des hauts faits obtenus par le personnage lui-même (et non plus le total du bataillon).
`1.13.0` : colonnes du tableau à partir de 40 % de la largeur de la fenêtre (recollées au bord droit si elle est trop étroite) ; colonne « Hauts faits » (points de haut fait) entre Or et Temps de jeu.
`1.12.3` : textes d'aide des champs raccourcis : « Rech. objet », « Rech. recette » (infobulles inchangées).
`1.12.2` : champs de recherche plus étroits (105 pixels chacun).
`1.12.1` : les deux champs de recherche côte à côte à droite du titre (barre de titre de nouveau sur une ligne).
`1.12.0` : champ « Rechercher une recette » sous celui des objets : recettes apprises de tous les personnages en mémoire, avec qui les connaît.
`1.11.1` : fiche d'un personnage : au survol d'un métier, seule sa moitié de ligne est en surbrillance.
`1.11.0` : métiers cliquables dans la fiche d'un personnage : objets de métier et recettes apprises par extension (relevées fenêtre du métier ouverte).
`1.10.4` : une seule fiche par personnage : un clic gauche sur un personnage dont la fiche est déjà ouverte la ramène au premier plan.
`1.10.3` : « Ranger » sans objet éligible : « Tous les objets ont déjà été déposés dans … », affiché aussi à l'écran.
`1.10.2` : clic droit sur le bouton « Data » (fenêtre Polypode et colonne de la barre flottante) : ranger, comme le bouton « Ranger ».
`1.10.1` : infobulle d'un personnage sans les rappels de clic en bas (« Clic gauche : épingler… », « Clic droit : oublier… »).
`1.10.0` : banque de bataillon (par compte Battle.net) et banque de guilde (par guilde) : un seul relevé gardé, le plus récent remplace les autres au lieu de s'y ajouter (doublons des versions précédentes nettoyés) ; relevé ignoré tant que la banque n'est pas chargée ; clic droit sur les icônes sacs / banques : remise à zéro.
`1.9.1` : personnage supprimé dans Polypode (Maj + clic) : ses données relevées sont oubliées, ici et sur les autres clients connectés.
`1.9.0` : métiers sur deux colonnes (infobulle et fiche) ; fiche épinglée d'un personnage : équipement en icônes comme la fenêtre de personnage de WoW (infobulle de l'objet au survol).
`1.8.3` : infobulle de « Ranger » : titre en jaune, résumé en bleu (« tout objet des sacs qui existe déjà dans une banque y est rangé »), puis le détail (en rouge si le bouton est grisé).
`1.8.2` : bouton « Ranger » aussi dans la barre de titre, entre « Dépôts » et l'icône du sac.
`1.8.1` : les quatre boutons deviennent des icônes (fenêtre de nouveau large de 620 au minimum).
`1.8.0` : boutons Sacs, Banque, Bataillon et Guilde du personnage joué (nombre d'objets au survol, contenu au clic).
`1.7.3` : « Ranger » en banque de guilde : les objets n'étaient jamais retenus (test d'autorisation du jeu inutilisable pour la guilde) ; seuls les objets liés sont écartés.
`1.7.2` : « Ranger » en banque de guilde : les objets des onglets non affichés sont reconnus (relevés à leur réception pendant la visite).
`1.7.1` : « Ranger » chez un banquier : banque du personnage et de bataillon quel que soit l'onglet affiché (un objet de la banque de bataillon n'était pas rangé avec l'onglet « Banque du personnage » affiché).
`1.7.0` : « Ranger » dépose aussi dans la banque de guilde (onglets avec droit de dépôt).
`1.6.0` : « Ranger » dépose aussi dans la banque de bataillon (objets qui y sont déjà ; banque du personnage en priorité).
`1.5.1` : « Ranger » grisé quand seule la banque de bataillon est ouverte (coffre de bataillon, accès à distance).
`1.5.0` : bouton « Ranger » (fiche Dépôts) : dépôt automatique dans la banque du personnage des objets qui y sont déjà.
`1.4.1` : correctif : la déconnexion n'efface plus l'or, les métiers, l'équipement et les sacs sauvegardés (relevé fait alors que le jeu les avait déjà vidés).
`1.4.0` : bouton « Dépôts » : objets des sacs déjà présents dans une banque, par personnage.
`1.3.0` : banque de guilde (fiche, détail, recherche).
`1.2.0` : équipement relevé avec son lien complet : enchantement, gemmes et niveau d'amélioration affichés.
`1.1.1` : fiches fermées par une croix, détail ouvert par un clic.
`1.1.0` : fiches épinglées (clic gauche sur un personnage), détail des sacs et banques, infobulle des objets.
`1.0.0` : première version (tableau des personnages, détail au survol, recherche d'objet, synchro).
