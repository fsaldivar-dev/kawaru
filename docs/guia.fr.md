[Español](guia.md) · [English](guia.en.md) · [Português](guia.pt-BR.md) · **Français** · [日本語](guia.ja.md) · [简体中文](guia.zh-Hans.md) · [한국어](guia.ko.md)

# Guide d’utilisation de Kawaru

Tout ce qu’il faut pour en tirer le meilleur, de l’installation à votre premier appel.

- [Installation](#installation)
- [Le tutoriel de bienvenue](#le-tutoriel-de-bienvenue)
- [Pendant un appel](#pendant-un-appel)
- [Effets](#effets)
- [Incrustations](#incrustations)
- [Gestes](#gestes)
- [Raccourcis clavier](#raccourcis-clavier)
- [La barre des menus et le fonctionnement en tâche de fond](#la-barre-des-menus-et-le-fonctionnement-en-tâche-de-fond)
- [Capturer l’arrière-plan](#capturer-larrière-plan)
- [En cas de pépin](#en-cas-de-pépin)
- [Confidentialité](#confidentialité)

## Installation

1. Téléchargez `Kawaru-0.2.0.dmg` depuis la [page des versions](https://github.com/fsaldivar-dev/kawaru/releases/latest).
2. Ouvrez-le et faites glisser **Kawaru** dans le dossier **Applications**. C’est indispensable : macOS n’autorise
   l’installation d’une caméra virtuelle qu’aux apps de ce dossier.
3. Ouvrez Kawaru depuis Applications.

Il vous faut macOS 14 ou une version ultérieure. Kawaru utilise la langue de votre Mac : espagnol, anglais, portugais,
français, japonais, chinois simplifié ou coréen.

## Le tutoriel de bienvenue

![Le tutoriel de bienvenue](img/app-tutorial.jpg)

Au premier lancement, Kawaru vous guide en cinq étapes :

1. **Le principe.** Un aperçu de ce que fait l’app.
2. **Votre caméra.** Cliquez sur « Autoriser la caméra » et acceptez la demande de macOS.
3. **La caméra virtuelle.** Cliquez sur « Installer la caméra virtuelle ». macOS vous demandera de l’approuver : ouvrez
   Réglages Système › Général › Ouverture et extensions › Extensions de caméra, puis activez Kawaru.
4. **Votre premier geste.** Levez le pouce face à la caméra et maintenez-le une demi-seconde. Vous verrez les points
   que Kawaru lit sur votre main et trois repères qui se remplissent chaque fois que le geste est reconnu.
5. **C’est prêt.** Un récapitulatif pour l’utiliser dans vos appels.

À la fin, une **visite guidée** vous montre chaque partie de la fenêtre et vous explique à quoi elle sert.

![La visite guidée](img/app-recorrido.jpg)

Vous pouvez revoir les deux quand vous voulez depuis le menu **Aide**.

## Pendant un appel

Dans Meet, Zoom, Teams ou toute autre app vidéo, ouvrez les réglages de la caméra et choisissez **Kawaru**.
Dès lors, les autres voient votre image avec tout ce que vous activez.

Inutile de garder la fenêtre de Kawaru ouverte : il suffit que l’app soit dans la barre des menus.

> Meet et Zoom vous montrent votre propre image en miroir : vous verrez donc vos incrustations à l’envers. Les
> autres les lisent normalement. Si cela vous gêne, désactivez l’option de mise en miroir de votre vidéo dans les
> réglages de l’app d’appels.

## Effets

![La section Effets](img/app-efectos.jpg)

La section **Effets** affiche une carte par effet. Quand vous en choisissez une, vous voyez à droite une vidéo de
l’effet réel et tout ce que vous pouvez régler :

- **Essayer en direct :** l’active sur votre caméra, dans la section En direct.
- **Position des mains :** le geste qui l’active. Avec « Aucune », il ne reste que le raccourci.
- **Votre propre position :** enregistrez un geste bien à vous (voir [Gestes](#gestes)).
- **Texte ou durée**, pour les effets qui en ont : les deux lignes du panneau, celles de la bulle, le
  mot des confettis et les minutes de la pause.

Le geste qui active un effet le désactive aussi. Confettis et Pause s’arrêtent tout seuls à la fin.

| Effet | Ce qu’il fait |
|---|---|
| Permutation | Vous disparaissez dans un nuage de fumée et il reste un rondin. Nécessite le [arrière-plan capturé](#capturer-larrière-plan). |
| Clones | Des copies de vous apparaissent sur les côtés. |
| Panneau d’absence | Masque l’image avec un panneau affichant votre texte. |
| Bulle de question | Une bulle à côté de vous. |
| Confettis | Une pluie de confettis et un mot. |
| Pause | Un compte à rebours en plein écran. |
| Projecteur | Vous en couleur, l’arrière-plan en gris. |

## Incrustations

![La section Incrustations](img/app-rotulos.jpg)

Les incrustations sont des textes affichés sur votre image. Contrairement aux effets, vous pouvez en avoir
**plusieurs à la fois**.

### En créer une

Cliquez sur **Nouvelle incrustation** et choisissez le type :

- **Tiers inférieur :** votre nom et votre poste.
- **Bandeau :** un intitulé, en haut ou en bas.
- **Badge :** une étiquette courte dans un coin.
- **Carton plein écran :** un message en plein écran.
- **Réseau social :** le logo du réseau et votre identifiant.

### Lui donner votre style

Dans l’éditeur, à droite :

- **Texte :** ce qu’elle dit.
- **Thème :** Minimal, Entreprise, Néon, Bois ou **Personnalisé**. Avec Personnalisé, vous choisissez la couleur
  du fond, du texte et d’accentuation, l’une des sept polices et l’arrondi des coins.
- **Position :** l’un des coins, ou **faites glisser sur l’aperçu** pour la placer où vous voulez.
  « Réinitialiser » la renvoie dans son coin.
- **Taille.**
- **Entrée :** glissement, fondu, rebond ou balayage. « Voir l’animation » la rejoue.
- **Reste à l’écran :** jusqu’à ce que vous la retiriez, ou de 5 secondes à 1 minute.

Dans une incrustation de réseau social, **Choisir une image…** remplace le logo par une image à vous.

### Plusieurs à la fois

Les incrustations qui partagent un même coin s’empilent dans l’ordre où vous les activez, sans se recouvrir. Celles
que vous avez placées en les faisant glisser restent là où vous les avez mises.

### L’afficher et la retirer

Avec **Afficher en direct**, avec son geste, avec son raccourci ou depuis la barre des menus.

## Gestes

Un geste s’active quand vous le maintenez un peu plus d’une **demi-seconde**. Pour le réutiliser, il faut d’abord
**baisser la main** : tant qu’elle reste dans la même position, il ne se répète pas.

### Les gestes prêts à l’emploi

Deux doigts sur le front, salut militaire, deux doigts levés, paume ouverte, pouce levé et signe à deux mains.

### Enregistrer le vôtre

1. Dans un effet ou une incrustation, cliquez sur **Enregistrer…** à côté de « Votre propre position ».
2. Vous avez trois secondes pour placer la main. Vous verrez les points que Kawaru lit : s’ils n’apparaissent pas,
   il ne la voit pas.
3. Ne bougez plus pendant l’enregistrement.
4. **Refaites-la trois fois**, en baissant la main entre chaque. Inutile de la reproduire à l’identique : ces
   répétitions apprennent à Kawaru comment vous la faites vraiment.

Une photo de vous faisant le geste est conservée, pour vous en souvenir.

### Conseils pour des gestes bien reconnus

- Chaque geste doit être **nettement différent** des autres. Si deux gestes se ressemblent, Kawaru vous prévient.
- Une main se lit mieux que deux. Si vous en utilisez deux, veillez à ce qu’elles **ne se touchent pas** : collées,
  elles sont vues comme une seule.
- Un bon éclairage de face, et la main dans le cadre.
- **S’entraîner au geste** vous permet d’essayer sans rien déclencher.

## Raccourcis clavier

Ils fonctionnent même quand l’app d’appels est au premier plan.

| Raccourci | Ce qu’il active |
|---|---|
| ⌃⌥1 … ⌃⌥7 | Les effets, dans l’ordre de la galerie |
| ⌃⌥⇧1 … ⌃⌥⇧9 | Vos incrustations, dans l’ordre de la liste |

## La barre des menus et le fonctionnement en tâche de fond

Kawaru place une icône dans la barre des menus. De là, vous pouvez :

- Activer ou désactiver n’importe quel effet ou incrustation d’un clic.
- Mettre en pause les **gestes des mains** (les raccourcis et les boutons restent actifs).
- Activer **Ouvrir avec la session**.
- Ouvrir la fenêtre, ou quitter l’app.

Fermer la fenêtre ne quitte pas l’app. Fenêtre fermée, votre caméra ne s’allume que lorsqu’un appel
utilise la caméra « Kawaru ».

## Capturer l’arrière-plan

Les effets qui vous effacent de l’image ont besoin de savoir ce qu’il y a derrière vous. Dans **Caméra**, cliquez sur
**Capturer l’arrière-plan** et sortez du cadre : au bout de trois secondes, Kawaru prend une photo de l’arrière-plan
vide. Elle reste uniquement en mémoire. Refaites-la si vous déplacez la caméra.

## En cas de pépin

**La caméra « Kawaru » n’apparaît pas dans mon app d’appels.**
Vérifiez que la section Caméra indique « Caméra virtuelle active ». Si vous l’avez installée alors que l’app
d’appels était déjà ouverte, quittez celle-ci puis rouvrez-la. Avec Chrome, il faut parfois quitter complètement le navigateur.

**L’app d’appels affiche une carte qui demande d’ouvrir l’app Kawaru (« Abre la app Kawaru »).**
Kawaru n’est pas lancée. Ouvrez-la ; elle peut rester dans la barre des menus.

**Un geste n’est pas reconnu.**
Utilisez « S’entraîner au geste » et observez les points de la main. S’ils n’apparaissent pas, la lumière est
insuffisante ou la main est hors du cadre. S’ils apparaissent mais que rien n’est compté, enregistrez le geste à nouveau.

**Un geste déclenche autre chose.**
Deux de vos gestes se ressemblent trop. Enregistrez-en un différent.

**Meet ou Chrome m’ajoutent un arrière-plan que je n’ai pas choisi.**
Cet arrière-plan vient du navigateur, pas de Kawaru. Vérifiez les effets vidéo de Chrome lui-même et ceux de macOS
(l’icône de caméra verte dans la barre des menus).

**L’icône de Kawaru apparaît en gris.**
C’est le style d’icônes de macOS (Réglages Système › Apparence). Il s’applique à toutes les apps.

## Confidentialité

- L’image de votre caméra est traitée sur votre Mac. Kawaru ne l’envoie nulle part.
- Ni comptes ni outils de mesure d’audience.
- Le dossier `~/Library/Application Support/Kawaru` contient les photos des gestes que vous enregistrez et les icônes
  que vous choisissez pour vos incrustations. Supprimez-les quand vous voulez.
