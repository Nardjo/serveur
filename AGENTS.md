# Règles pour l'agent

Tu travailles sur un serveur de développement décrit par ce dépôt. Lis cette page avant
d'agir. Elle vaut pour Claude Code, Codex, OpenBot ou n'importe quel autre agent.

## La règle qui prime sur toutes les autres

**Le dépôt d'abord, le serveur ensuite.** Tu modifies un fichier ici, tu commites, puis tu
déploies. Une modification faite directement sur la machine et absente du dépôt est perdue au
prochain redémarrage, et personne ne saura pourquoi la machine a changé de comportement.

Si tu dois bricoler en direct pour comprendre un problème, remets ta trouvaille dans le dépôt
avant de passer à la suite.

## Qui tu es sur la machine

Tu te connectes avec le compte `agent`, par clé, depuis le poste de ton utilisateur. Ce
compte :

- n'a **aucun droit d'administration** : pas de paquet système, pas de pare-feu, pas de
  réglage d'accès ;
- parle au moteur de conteneurs et possède `/opt/stacks` ;
- n'a pas de mot de passe, donc rien à deviner.

Si une tâche exige des droits d'administration, **arrête-toi et demande**. Ne cherche pas de
contournement : la machine est volontairement fermée, et la refermer après coup ne se voit
pas.

## Ajouter un service

1. Crée `hosts/<machine>/<service>/compose.yml`.
2. Le service rejoint le réseau `proxy` et déclare ses étiquettes de routage.
3. Les variables sensibles sont **déclarées par leur nom**, jamais par leur valeur.
4. Commite.
5. Déploie : envoie le dossier dans `/opt/stacks/<service>` sur la machine, puis démarre-le.
6. Vérifie que le service répond, et dis-le avec la sortie, pas avec une impression.

Exemple de squelette, dans `hosts/exemple/demo/compose.yml`.

## Déployer

```sh
rsync -a --delete hosts/<machine>/<service>/ agent@<machine>:/opt/stacks/<service>/
ssh agent@<machine> 'cd /opt/stacks/<service> && docker compose up -d'
```

Si le service a des secrets, il se lance à travers le coffre, pas avec un fichier
d'environnement posé à côté.

## Vérifier

Après toute action sur la machine :

```sh
ssh agent@<machine> 'docker compose -f /opt/stacks/<service>/compose.yml ps'
curl -sS -o /dev/null -w '%{http_code}\n' https://<adresse-du-service>
```

Un déploiement n'est pas fini tant qu'une de ces deux commandes n'a pas répondu.

## Ce que tu ne fais jamais sans qu'on te le demande

- Supprimer un volume, une base, ou le contenu de `/opt/stacks`.
- Ouvrir un port sur la machine, ou modifier le pare-feu et son filtre de conteneurs.
- Publier un port de conteneur directement sur l'extérieur : tout passe par le reverse proxy.
- Écrire un secret dans un fichier du dépôt, dans un message, ou dans l'historique.
- Toucher au service d'accès, aux clés autorisées, ou aux comptes.
- Redémarrer la machine.

## Quand quelque chose casse

1. Lis les journaux du service avant de changer quoi que ce soit.
2. Dis ce que tu as vu, puis ce que tu proposes.
3. Si le correctif touche la machine et non un service, c'est une tâche pour l'humain.

## Les secrets

Tu ne vois jamais une valeur. Tu manipules des noms de variables. Si une valeur te manque,
demande à ton utilisateur de la poser dans le coffre, et continue avec le nom.
