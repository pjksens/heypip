<p align="center">
  <img src="docs/media/hero.fr.png" alt="Pip, un petit compagnon dans l'encoche de ton Mac qui te souffle quoi dire pendant tes appels">
</p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/pjksens/heypip?label=t%C3%A9l%C3%A9charger&color=2B59FF" alt="Télécharger"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple" alt="macOS 15+">
  <img src="https://img.shields.io/badge/transcription-sur%20ton%20Mac-0A84FF" alt="Sur ton Mac">
  <img src="https://img.shields.io/badge/licence-MIT-green" alt="MIT">
  <a href="../../stargazers"><img src="https://img.shields.io/github/stars/pjksens/heypip?style=flat&color=FFD60A&label=%E2%98%85%20%C3%A9toiles" alt="Étoiles"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <b>Français</b>
</p>

<p align="center">
  Créé par <b>pjk</b> (Sacha Praljak) ·
  <a href="https://sachapraljak.com/?utm_source=github&utm_medium=readme-fr&utm_campaign=heypip">sachapraljak.com</a> ·
  <a href="https://www.instagram.com/sachaprljk/">Instagram</a> ·
  <a href="https://www.tiktok.com/@sachaprljk">TikTok</a>
</p>

<p align="center">
  <b>Pip te sert ? Une ⭐ aide d’autres personnes à le trouver.</b>
</p>

**Pip vit dans l'encoche de ton MacBook et fait entrer ton agent IA dans tes réunions.** Pendant une visio, un
rendez-vous client ou une réunion d'équipe sur Google Meet, Zoom ou Teams, Pip transcrit ce que tu dis et ce que disent
les autres, en direct et sur ton Mac. Ton agent (Claude Code, Codex, tout agent capable de lire un fichier) suit la
conversation et t'aide à la mener : la prochaine question à poser, l'option à choisir, une info qu'il vient de vérifier,
le point que personne n'a tranché. Pip sort de l'encoche pour te le souffler.

<p align="center">
  <img src="docs/media/demo.fr.gif" width="640" alt="Pip pendant un appel : la transcription s'écrit en direct, puis Pip sort de l'encoche pour souffler les notes de l'agent">
  <br><sub>Démo scénarisée (<code>Pip --demo fr</code>) : pas de vrai appel, pas de vraies personnes.</sub>
</p>

## Ton agent, en réunion avec toi

- **Il t'aide à décider.** On te propose deux options : ton agent les compare à ce que tu lui as dit avant l'appel et
  te dit laquelle prendre, et pourquoi.
- **Il guide la réunion.** La question à poser ensuite, le point de ton ordre du jour pas encore abordé, le bon moment
  pour parler prix.
- **Il cherche pendant que tu parles.** Une entreprise, le prix d'un concurrent, une règle dont tu n'es pas sûr : ton
  agent cherche et te souffle la réponse. Il faut un agent qui a accès au web, comme Claude Code.
- **Il vérifie ce qui se dit.** Un chiffre qui ne colle pas, une promesse qui contredit ce qui a été dit plus tôt.
- **Il prépare la suite.** À la fin de l'appel : le résumé, les décisions, les prochaines étapes, le mail.

Pip apporte la conversation à ton agent et te ramène ses notes ; ce que l'agent sait faire dépend de l'agent que tu
branches. Une phrase arrive à ton agent 1 à 3 s après avoir été dite. Dans nos tests avec Claude Code, la note arrivait
3 à 8 s après la phrase qui l'appelait (environ 5 s en général), et 17 à 20 s quand l'agent cherchait d'abord sur le
web.

## Regarde-le négocier

Un appel de test : un client fictif, chaque réplique écrite à l'avance, une vraie session Claude Code. Les notes de
Claude, sans retouche :

| Ils ont dit | Pip a soufflé |
|---|---|
| « Notre budget, c'est 800 euros maximum. » | Budget 800 < 990. Pas de remise sèche: Complète allégée (2 formats) ou Essentielle. |
| « Vous pourriez nous facturer à 90 jours ? » | 90 j interdit en B2B (max 60 j, L441-10, vérifié). Vise 30 j ou acompte 50%. *(après une recherche web, 18 s)* |
| « …plus la vidéo à 490, ça fait 700 euros. » | Calcul faux: 490 + 3×100 = 790, pas 700. Corrige-les. Tes formats = 500 € (3), pas 300. |

L'appel en entier, les délais et le résumé écrit par Claude à la fin :
[docs/examples/negotiation.fr.md](docs/examples/negotiation.fr.md).

## Ce que fait Pip

- **En direct, sur ton Mac.** La reconnaissance vocale d'Apple, phrase par phrase, 1 à 3 s après qu'elle est dite.
  Sur macOS 26, aucun son ne quitte ton Mac (macOS 15 : voir Vie privée).
- **Toi et Eux, séparément.** Ton micro, c'est « Toi » ; le son de l'appel, c'est « Eux », chacun sur sa piste.
- **Ton agent, ou pas.** Un bouton coupe l'agent : Pip continue de transcrire, et rien n'est écrit pour l'agent.
- **Pause** quand l'appel passe en off : rien n'est entendu ni enregistré jusqu'à la reprise.
- **Un dossier par réunion :** la transcription, les deux pistes audio et les notes de ton agent.
- **Se met à jour tout seul** depuis les versions publiées ici, entre deux réunions, après avoir vérifié que la nouvelle
  version est signée par le même développeur.
- **Pip montre où il en est.**

<p align="center">
  <img src="docs/media/moods.fr.png" width="640" alt="Les états de Pip : prêt, se prépare, écoute, personne ne parle, en pause, a une note, enregistré, problème">
</p>

## Installer

1. Télécharge **Pip.zip** depuis la [dernière version](../../releases/latest), dézippe-le et range **Pip** dans
   Applications.
2. Ouvre Pip. Un petit Pip en points apparaît à gauche de l'encoche : passe ton pointeur dessus.
3. Appuie sur **Démarrer**. macOS demande **Enregistrement de l'écran et de l'audio système** (pour entendre l'appel) et
   **Microphone**. S'il te demande de quitter et rouvrir Pip, fais-le, puis appuie à nouveau sur Démarrer.

Configuration : macOS 15 ou plus récent, Apple silicon ou Intel. Sur macOS 26, Pip utilise le nouveau SpeechAnalyzer
d'Apple (plus rapide, plus précis) ; sur macOS 15, l'ancienne reconnaissance vocale. Le modèle de ta langue se
télécharge une seule fois. Sur macOS 15, la transcription sur le Mac n'est pas garantie (voir Vie privée).

**Le mieux : un casque ou des écouteurs.** Sans, ton micro entend aussi l'appel. Pip retire cet écho de « Toi », mais ta
voix mélangée au haut-parleur est un peu moins bien reconnue.

> Enregistrer ou transcrire un appel demande en général l'accord de tous les participants. Préviens-les au début :
> Pip te le rappelle.

## Utiliser

| | |
|---|---|
| Ouvrir Pip | passe ton pointeur sur Pip, à gauche de l'encoche ; clique pour le garder ouvert, clique à côté pour le fermer |
| Démarrer, mettre en pause, arrêter | les boutons sous Pip, ou le menu |
| Activer ou couper l'agent | **✦ Claude** en haut de Pip |
| Revoir une réunion récente, en commencer une nouvelle | clic sur le nom de la réunion, en haut à gauche de l'île |
| Langue, vocabulaire, dossier, quitter | la roue dentée, ou clic droit sur Pip |
| Masquer le petit Pip à côté de l'encoche | clic droit sur Pip → **Pip à côté de l'encoche** |
| Mettre Pip dans la barre de menus | roue dentée → **Pip dans la barre de menus** : Pip quitte l'encoche, un clic sur son icône l'ouvre |

**Vocabulaire :** ajoute les noms des personnes, entreprises et produits dont tu parles pour qu'ils soient bien
transcrits (`~/Library/Application Support/Pip/vocabulary.txt`).

Chaque réunion est un dossier dans `~/Documents/Pip/<date>_<nom>/` :

| Fichier | Contenu |
|---|---|
| `transcript.md` | une ligne par phrase, `[12:03:15] Toi: …` Toujours écrit, reste sur ton Mac. |
| `agent-feed.md` | les mêmes lignes, seulement quand l'agent est activé. **C'est le fichier que suit ton agent.** |
| `notes.md` | écrit par ton agent ; la dernière ligne sort de l'encoche |
| `summary.md` | écrit par ton agent à la fin de la réunion (si tu le lui demandes) |
| `you.m4a`, `them.m4a` | le son de chaque côté |
| `screens/` | avec Claude Code : des captures de ton écran, gardées seulement là où il a changé ou quand ça comptait (voir plus bas) |

`~/Documents/Pip/current` pointe toujours vers la réunion en cours.

## Brancher ton agent

Ton agent suit `agent-feed.md` et ajoute une ligne courte par note dans `notes.md`.

**Claude Code** (une version récente : il utilise l'outil Monitor).

1. Installe la commande `/pip`, une seule fois :

   ```bash
   mkdir -p ~/.claude/skills/pip && curl -fsSL https://raw.githubusercontent.com/pjksens/heypip/main/integrations/claude-code/pip/SKILL.md -o ~/.claude/skills/pip/SKILL.md && curl -fsSL https://raw.githubusercontent.com/pjksens/heypip/main/integrations/claude-code/pip/screens.sh -o ~/.claude/skills/pip/screens.sh
   ```

2. Avant l'appel, lance `claude` dans un terminal et tape `/pip` avec qui tu rencontres et ce que tu veux obtenir :

   ```
   /pip Appel avec Atelier Lune, ils veulent une vidéo de lancement. Objectif : signer la formule à 990 €, payée à 30 jours.
   ```

3. Appuie sur **Démarrer** dans Pip, avec **✦ Claude** activé. Les notes sortent de l'encoche ; quand tu arrêtes, le
   résumé est dans `summary.md`.

**Captures d'écran.** Claude garde aussi ce qui a été montré à l'écran : une capture toutes les 15 secondes pendant la
réunion, plus une immédiate quand un écran est partagé, qu'un document ou un chiffre est montré, ou quand tu dis
« Claude, capture ». À la fin, seules les captures clés et celles où l'écran a changé sont gardées, dans `screens/`
avec un `index.md` ; le reste est effacé, et le résumé cite chaque image gardée. Tout reste dans le dossier de la
réunion. L'app qui fait tourner Claude Code (ton terminal, ou l'app Claude) a besoin d'**Enregistrement de l'écran**
dans Réglages Système. Tape `/pip --no-screens …` pour t'en passer sur un appel.

Sans la commande, dis à Claude qui tu rencontres et ce que tu veux obtenir, puis colle :

   > Suis mon appel avec Pip et aide-moi à atteindre mon objectif. Surveille `~/Documents/Pip/current/agent-feed.md`
   > avec l'outil Monitor (`tail -n 0 -F`). Quand ça en vaut la peine, ajoute UNE ligne de 90 caractères maximum dans
   > `~/Documents/Pip/current/notes.md` : la prochaine question à poser, l'option que je devrais choisir et pourquoi, un
   > point flou, un chiffre qui ne colle pas, une info que tu as vérifiée. Cherche sur le web quand une info mérite
   > d'être vérifiée. Sinon, reste silencieux. À la fin de la réunion, écris le résumé, les décisions et les prochaines
   > étapes dans `~/Documents/Pip/current/summary.md`.

**Un autre agent :** il suffit qu'il sache surveiller un fichier et en écrire un. La
[commande `/pip`](integrations/claude-code/pip/SKILL.md) est un simple texte d'instructions que tu peux lui donner.

## Vie privée

- Sur macOS 26, la transcription se fait sur ton Mac (SpeechAnalyzer d'Apple).
- Sur macOS 15, Pip demande la transcription sur le Mac en priorité. Si le modèle de ta langue n'y est pas disponible,
  la reconnaissance vocale d'Apple passe par ses serveurs : la transcription sur le Mac n'y est donc pas garantie.
- Pip lui-même n'a ni compte, ni serveur, ni statistiques, et n'envoie rien nulle part.
- Ton agent ne voit que `agent-feed.md`, et seulement quand il est activé. Si ton agent tourne dans le cloud, ce qu'il
  lit part chez son fournisseur.
- Le son et les transcriptions restent dans ton dossier de réunions jusqu'à ce que tu les supprimes.

Tu as trouvé une fuite ? Voir [SECURITY.md](SECURITY.md).

## Questions fréquentes

**Est-ce qu'il rejoint l'appel comme un bot ?** Non. Personne ne voit Pip : il écoute ton Mac, comme tes oreilles.

**Est-ce qu'il marche sans agent ?** Oui. Coupe l'agent et Pip devient un transcripteur privé, en direct.

**Est-ce qu'il marche pour une réunion en présentiel ?** Oui, avec le micro de ton Mac, mais tout le monde est alors
« Toi » : Pip ne distingue les deux côtés que pendant un appel.

**Mon Mac n'a pas d'encoche.** Pip se place alors en haut au centre de ton écran, ou dans la barre de menus si tu
préfères (roue dentée → **Pip dans la barre de menus**).

**Quelles langues ?** Toutes celles que la reconnaissance vocale de ton Mac comprend. L'interface est en anglais et en
français.

## Compiler depuis le code

```bash
git clone https://github.com/pjksens/heypip.git && cd heypip
bash build.sh && open Pip.app
```

Il faut les outils en ligne de commande de Xcode 26. Voir [AGENTS.md](AGENTS.md) pour la carte du code et comment
vérifier un changement, et [CONTRIBUTING.md](CONTRIBUTING.md) pour contribuer (en anglais).

## Prochaines étapes

- Distinguer plusieurs personnes côté « Eux », après l'appel.
- Un guide au premier lancement (autorisations, écouteurs, consentement).

## Créé par

**pjk** (Sacha Praljak). Je crée des outils IA et je les montre en vidéos courtes. Pip est créé avec Claude Code.

- Site : [sachapraljak.com](https://sachapraljak.com/?utm_source=github&utm_medium=readme-fr&utm_campaign=heypip)
- Instagram : [@sachaprljk](https://www.instagram.com/sachaprljk/)
- TikTok : [@sachaprljk](https://www.tiktok.com/@sachaprljk)

Si Pip t'aide, une ⭐ sur le dépôt et un abonnement, ça aide beaucoup.

## Licence

[MIT](LICENSE)
