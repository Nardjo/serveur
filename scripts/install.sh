#!/usr/bin/env bash
# Point d'entrée : prépare une machine neuve de bout en bout.
#   moteur de conteneurs → durcissement → réseau du reverse proxy → état final
# Idempotent.
#
# Usage, depuis ton poste, dans le dépôt :
#   scp -r scripts root@adresse:/tmp/serveur
#   ssh root@adresse 'bash /tmp/serveur/install.sh'
#
# Les trois autres scripts doivent être à côté de celui-ci : il les appelle. C'est pour ça
# qu'on copie le dossier avant de lancer, au lieu de passer le script par l'entrée standard.
#
# Avant de lancer : vérifie que tu entres déjà par clé. Sans ta clé sur la machine, le
# durcissement te laisse dehors.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer en administrateur (sudo)"; exit 1; }

ICI=$(cd "$(dirname "$0")" && pwd)
for f in harden-host.sh check.sh; do
  [ -f "$ICI/$f" ] || {
    echo "ERREUR : $f doit être à côté de install.sh, dans le même dossier."
    echo "Copie tout le dossier scripts/ sur la machine, puis relance :"
    echo "  scp -r scripts root@<adresse>:/tmp/serveur"
    echo "  ssh root@<adresse> 'bash /tmp/serveur/install.sh'"
    exit 1
  }
done

echo "== moteur de conteneurs"
if command -v docker >/dev/null 2>&1; then
  echo "déjà installé : $(docker --version)"
else
  # Script d'installation officiel de Docker. Dans un dépôt qui parle de prudence, on le dit :
  # oui, on exécute un script téléchargé, et c'est celui que Docker publie et maintient.
  # Si tu préfères, installe Docker toi-même avant de lancer ce script, il le détectera.
  curl -fsSL https://get.docker.com | sh
  systemctl enable -q --now docker
fi

echo "== durcissement"
bash "$ICI/harden-host.sh"

echo "== réseau du reverse proxy"
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy >/dev/null
echo "réseau proxy prêt"

echo "== état de la machine"
bash "$ICI/check.sh"

cat <<'FIN'

Et maintenant :

  1. crée le compte de ton agent
       ssh root@<adresse> 'bash /tmp/serveur/setup-agent-user.sh "<clé publique>"' 
  2. démarre le reverse proxy
       copie hosts/exemple/proxy/ dans /opt/stacks/proxy, règle l'adresse de courriel
       des certificats, puis : cd /opt/stacks/proxy && docker compose up -d
  3. ouvre ton agent dans le dépôt et demande-lui ton premier service

FIN
