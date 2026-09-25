# ZapZap — Politique de confidentialité / Privacy Policy

**Last Updated / Dernière mise à jour :** 2026-09-25

This page is served at <https://zapzap.ombivince.synology.me/privacy>. It is written in
French first, then in English; both say the same thing.

---

## Français

ZapZap est un jeu de cartes multijoueur : l'application Android, l'application web
(<https://zapzap.ombivince.synology.me/app/>) et le site
<https://zapzap.ombivince.synology.me/>. Elles parlent toutes au même serveur, exploité
par le développeur de ZapZap.

### Ce que ZapZap enregistre

- **Ton compte** : ton pseudo, l'empreinte de ton mot de passe (bcrypt — le mot de passe
  lui-même n'est jamais enregistré), la date de création du compte, la date de ta dernière
  connexion et ton temps de jeu cumulé.
- **Si tu te connectes avec Google** : ton identifiant Google et ton adresse e-mail, que
  Google nous transmet à la connexion. Ton nom Google sert seulement à te proposer un pseudo ;
  il n'est pas enregistré tel quel.
- **Tes parties** : les parties que tu crées ou rejoins, les coups joués (cartes jouées et
  piochées, mains, scores), les résultats de chaque manche et de chaque partie. Ils forment
  ton historique et tes statistiques, et les parties terminées apparaissent aussi dans
  l'historique des autres joueurs de la partie. Les coups servent aussi à améliorer les
  bots du jeu.
- **Sur ton appareil** : le jeton de session qui te garde connecté, et ton profil (pseudo,
  compte Google ou non) pour l'affichage. Ils restent sur ton appareil et sont effacés à la
  déconnexion.
- **Les journaux du serveur web** : l'adresse IP, la date, la page demandée et le
  navigateur de chaque requête, comme tout serveur web.

### Pourquoi

Uniquement pour faire fonctionner le jeu : te connecter, jouer avec les autres, afficher
ton historique, tes statistiques et le classement, et garder le service en état de marche.

### Ce que ZapZap ne fait pas

- Aucune vente, aucun partage de tes données avec qui que ce soit.
- Aucune publicité, aucun outil de mesure d'audience ou de suivi, aucun rapport de plantage
  envoyé à un tiers.
- Les seuls tiers impliqués : **Google**, quand tu choisis de te connecter avec Google (sa
  propre politique de confidentialité s'applique alors) ; et, quand les bots « LLM » sont
  activés sur le serveur, la situation de jeu d'une partie contre un tel bot (cartes,
  scores — ni pseudo ni compte) peut être envoyée à un modèle d'IA hébergé (AWS Bedrock)
  pour choisir le coup du bot.

Ce que les autres joueurs voient de toi : ton pseudo, ta présence en ligne, tes parties et
tes résultats (historique, classement).

### Durée de conservation

Ton compte et ses données sont conservés tant que ton compte existe. Quand tu le supprimes,
ton pseudo, ton mot de passe, ton identifiant Google et ton e-mail sont effacés
immédiatement. Tes parties terminées restent dans l'historique des autres joueurs, sous le
nom « Joueur supprimé », sans lien avec toi.

### Supprimer ton compte

- **Dans l'application** (Android ou web) : menu ⋮ en haut à droite → **Supprimer mon
  compte**, puis confirme avec ton mot de passe (ou avec Google pour un compte Google).
- **Depuis le web, sans l'application** :
  <https://zapzap.ombivince.synology.me/account/delete> — connecte-toi, puis confirme.
- Une partie en attente ou en cours doit d'abord être quittée ou terminée.

### Contact

Pour toute question ou demande sur tes données : via les issues du dépôt GitHub,
<https://github.com/vemore/zapzap/issues>.

---

## English

ZapZap is a multiplayer card game: the Android app, the web app
(<https://zapzap.ombivince.synology.me/app/>) and the site
<https://zapzap.ombivince.synology.me/>. They all talk to the same server, run by
ZapZap's developer.

### What ZapZap stores

- **Your account**: your username, a hash of your password (bcrypt — the password itself is
  never stored), when the account was created, when you last signed in, and your total play
  time.
- **If you sign in with Google**: your Google account id and your email address, which
  Google sends at sign-in. Your Google name is only used to suggest a username; it is not
  stored as such.
- **Your games**: the games you create or join, the moves played (cards played and drawn,
  hands, scores), and the results of each round and each game. They make up your history
  and your statistics, and finished games also appear in the history of the other players
  of that game. The moves are also used to improve the game's bots.
- **On your device**: the session token that keeps you signed in, and your profile
  (username, whether it is a Google account) for display. They stay on your device and are
  erased when you sign out.
- **Web server logs**: the IP address, time, requested page and browser of each request, as
  any web server keeps.

### Why

Only to run the game: sign you in, let you play with others, show your history, your
statistics and the leaderboard, and keep the service working.

### What ZapZap does not do

- No sale and no sharing of your data with anyone.
- No advertising, no analytics or tracking tool, no crash reports sent to a third party.
- The only third parties involved: **Google**, when you choose to sign in with Google (its
  own privacy policy then applies); and, when "LLM" bots are enabled on the server, the game
  situation of a game against such a bot (cards, scores — no username, no account) may be
  sent to a hosted AI model (AWS Bedrock) to choose the bot's move.

What other players see of you: your username, whether you are online, your games and your
results (history, leaderboard).

### Retention

Your account and its data are kept as long as your account exists. When you delete it,
your username, password, Google id and email are erased at once. Your finished games stay
in the other players' history under the name "Deleted player", with no link to you.

### Deleting your account

- **In the app** (Android or web): the ⋮ menu at the top right → **Delete my account**, then
  confirm with your password (or with Google for a Google account).
- **From the web, without the app**:
  <https://zapzap.ombivince.synology.me/account/delete> — sign in, then confirm.
- A game that is waiting or in progress must be left or finished first.

### Contact

For any question or request about your data: through the GitHub repository's issues,
<https://github.com/vemore/zapzap/issues>.
