Bugs et Problèmes Identifiés

  1. Erreur 504 sur SSE (Server-Sent Events) - CRITIQUE

  - Endpoint: /suscribeupdate
  - Symptôme: Le statut de connexion affiche en permanence "Connecting..."
  - Impact: Les mises à jour en temps réel ne fonctionnent pas. Les joueurs ne voient pas les
  actions des autres en direct.
  - Cause probable: Le reverse proxy Synology coupe la connexion SSE (timeout gateway). Les
  connexions SSE nécessitent une configuration spéciale pour les keep-alive.

  2. Images des cartes adversaires : "undefined of hearts"

  - Symptôme: Les cartes des autres joueurs (dos de carte) affichent "undefined of hearts" comme alt
   text
  - Localisation: Section des joueurs adversaires dans l'interface de jeu
  - Impact: Accessibilité réduite, texte alt incorrect


  4. Nombre de joueurs non synchronisé avec les slots

  - Symptôme: Changer le nombre de joueurs (spinbutton) ne met pas à jour dynamiquement le nombre de
   slots affichés
  - Localisation: Page de création de partie
  - Impact: Mineur - confusion pour l'utilisateur



  Nombre de bots identiques maximal à 2



Afficher sur la page des parties les derniers joueurs actuellement connecté (limité à 5) avec le status "lobby" ou "party"

Changer la liste des joueurs dans les parties en cours pour les mettre un par ligne. Pour chaque joueur on aura une ligne de ce type:
<Nom du joueur> - <score> : Nombre de cartes sous forme d'une ligne de dos de cartes suivit de "(<nb cartee>)"
Les lignes doivent être dans l'ordre du début de tour. Cad que le premier joueur à jouer apparait sur la première ligne. L'ordre changera au tour suivant. La ligne du joueur dont c'est le tour doit être mise en avant. Ce changement doit être testé pour être également compatible sur une vue de smartphone donc être responsive. La hauteur des lignes doivent être de la même hauteur tout en étant assez compactes pour laisser de l'espace aux éléments en dessous

Ajouter la possibilité de s'enregistrer avec Google

