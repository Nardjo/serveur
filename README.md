# serveur

Le squelette d'un serveur de développement : durci, prêt à recevoir tes services, et
pensé pour que **ton agent** s'en serve sans que tu lui réexpliques.

Tu commandes une machine chez n'importe quel hébergeur, tu clones ce dépôt, tu lances une
commande. Ensuite tu parles à ton agent, et c'est lui qui installe, déploie et vérifie.

## Avant de t'en servir

Ces scripts n'ont jamais tourné sur une vraie machine. Ils sont relus, pas éprouvés.

Ils touchent à l'accès SSH et au pare-feu : une erreur t'enferme dehors de ton propre serveur.
Essaie-les sur une machine jetable avant la vraie. Pendant le durcissement, garde une
deuxième session ouverte et vérifie que tu entres toujours avant de fermer la première.

## En quatre commandes

```sh
git clone <ce-dépôt> serveur && cd serveur

# 0. les scripts partent sur la machine : ils s'appellent entre eux
scp -r scripts root@TON_ADRESSE:/tmp/serveur

# 1. la machine : durcissement, moteur de conteneurs, réseau du reverse proxy
ssh root@TON_ADRESSE 'bash /tmp/serveur/install.sh'

# 2. le compte de ton agent : une clé à lui, pas de droits d'administration
ssh root@TON_ADRESSE "bash /tmp/serveur/setup-agent-user.sh '$(cat ~/.ssh/agent.pub)'"

# 3. les preuves, à relire plus tard
ssh root@TON_ADRESSE 'bash /tmp/serveur/check.sh'
```

La troisième commande imprime l'état réel de la machine : ce que le service d'accès applique,
l'état du pare-feu, celui du videur, et le filtre qui protège tes conteneurs. Garde cette
sortie : c'est ton point de comparaison le jour où quelque chose cloche.

## Ce que ça installe

| Bloc | Ce que ça fait |
|---|---|
| Accès | connexion par clé seulement, mot de passe refusé |
| Videur | bannit les adresses qui insistent, avec une liste d'exceptions |
| Correctifs | les mises à jour de sécurité s'appliquent sans toi |
| Pare-feu | tout fermé en entrée, sauf la connexion et le web |
| Filtre conteneurs | empêche un port publié par un conteneur de contourner le pare-feu |
| Moteur de conteneurs | installé s'il manque |
| Reverse proxy | un point d'entrée unique, certificats automatiques |

## Comment c'est rangé

```
AGENTS.md                           les règles que ton agent lit avant d'agir
scripts/                            ce qui s'exécute sur la machine
hosts/<machine>/<service>/          un dossier par service, un compose.yml dedans
hosts/<machine>/proxy/              le reverse proxy de cette machine
```

Le dépôt fait foi. Ce qui tourne sur la machine et n'est pas ici n'existe pas : au premier
redémarrage, ça disparaît, et personne ne saura pourquoi.

## Donner ce dépôt à ton agent

Ouvre ton agent dans ce dossier. Il lit `AGENTS.md` et il sait : où déposer un nouveau
service, comment le déployer, ce qu'il doit vérifier après, et ce qu'il n'a pas le droit de
faire.

Puis demande-lui en français. « Ajoute un service qui sert ce dossier en HTTPS sur
`demo.mondomaine.fr` et déploie-le. »

## Les secrets

Aucun secret n'entre dans ce dépôt. Les fichiers d'environnement sont ignorés par git. Tes
valeurs vivent dans un coffre et sont injectées au lancement du service.

## Prérequis

Une machine Debian ou Ubuntu nue, un accès administrateur par clé, et ta clé publique déjà
déposée dessus. Sans ta clé sur la machine, le durcissement t'enferme dehors.
