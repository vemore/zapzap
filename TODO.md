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


