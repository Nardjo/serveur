#!/usr/bin/env bash
# Imprime l'état réel de la machine. Pas ce que disent les fichiers : ce que les services
# appliquent. Garde cette sortie, c'est ton point de comparaison.
#
# Usage : ssh root@adresse 'bash -s' < scripts/check.sh
set -uo pipefail

titre() { printf '\n== %s\n' "$1"; }

titre "accès"
sshd -T 2>/dev/null | grep -E '^(passwordauthentication|permitrootlogin|kbdinteractiveauthentication) ' \
  || echo "impossible de lire la configuration appliquée"

titre "videur"
fail2ban-client status sshd 2>/dev/null | grep -E 'Currently banned|Total banned|Status' \
  || echo "videur absent ou inactif"

titre "correctifs automatiques"
if systemctl is-enabled unattended-upgrades >/dev/null 2>&1; then
  echo "actifs"
else
  echo "INACTIFS"
fi

titre "pare-feu"
ufw status 2>/dev/null | head -12 || echo "pare-feu absent"

titre "filtre de conteneurs"
if iptables -S SERVEUR-FILTRE >/dev/null 2>&1; then
  echo "v4 : $(iptables -S SERVEUR-FILTRE | grep -c -- '-A') règles"
  echo "v6 : $(ip6tables -S SERVEUR-FILTRE 2>/dev/null | grep -c -- '-A') règles"
  systemctl is-enabled serveur-firewall >/dev/null 2>&1 \
    && echo "réappliqué au démarrage : oui" || echo "réappliqué au démarrage : NON"
else
  echo "ABSENT — un port publié par un conteneur est joignable depuis internet"
fi

titre "conteneurs"
docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || echo "moteur de conteneurs absent"

titre "ports à l'écoute"
ss -tulpn 2>/dev/null | grep LISTEN | awk '{print $1, $5}' | sort -u | head -20

printf '\n'
echo "Rappel : la seule preuve qui compte pour l'accès, c'est d'essayer d'entrer par mot de"
echo "passe depuis un autre terminal. Ça doit être refusé."
