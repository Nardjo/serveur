#!/usr/bin/env bash
# Durcissement de base d'une machine Debian/Ubuntu qui fait tourner des conteneurs.
# Idempotent : relançable autant de fois que tu veux.
#
#   - accès : clé seulement, administrateur par clé, mot de passe refusé
#     (touché uniquement si la configuration actuelle est encore ouverte)
#   - videur sur le service d'accès
#   - correctifs de sécurité automatiques
#   - pare-feu : 22, 80, 443, plus le réseau privé s'il existe
#   - filtre de conteneurs : un port publié par un conteneur contourne le pare-feu,
#     on ne laisse entrer depuis l'extérieur que 80, 443 et ALLOW_PORTS
#
# Usage :
#   sudo bash harden-host.sh
#   sudo TRUSTED_IPS="203.0.113.7 203.0.113.8" ALLOW_PORTS="3000" bash harden-host.sh
#
# TRUSTED_IPS : adresses jamais bannies et autorisées par le pare-feu (ton bureau, tes
# autres machines). Vide par défaut.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer en administrateur (sudo)"; exit 1; }

CONF=/etc/default/serveur-firewall
TRUSTED_IPS=${TRUSTED_IPS-$( (. "$CONF" && echo "$TRUSTED_IPS") 2>/dev/null || true)}
ALLOW_PORTS=${ALLOW_PORTS-$( (. "$CONF" && echo "$ALLOW_PORTS") 2>/dev/null || true)}
PUBLIC_IF=$(ip route get 1.1.1.1 2>/dev/null | grep -o 'dev [^ ]*' | cut -d' ' -f2 || true)
[ -n "$PUBLIC_IF" ] || {
  echo "ERREUR : impossible de détecter l'interface réseau publique."
  echo "Sans elle, le filtre de conteneurs serait invalide et le pare-feu casserait."
  echo "Vérifie que la machine a une route par défaut, puis relance."
  exit 1
}

echo "== paquets"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq fail2ban python3-systemd unattended-upgrades ufw >/dev/null

echo "== accès"
# On ne touche à la configuration que si elle est encore ouverte : une machine déjà
# durcie à la main garde ses règles.
if ! grep -qrE '^\s*Include\s+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config; then
  echo "ATTENTION : ce système ne lit pas /etc/ssh/sshd_config.d/ (pas de directive Include)."
  echo "Les règles d'accès doivent être écrites directement dans /etc/ssh/sshd_config."
  echo "Rien n'a été durci côté accès. Corrige, ou durcis à la main, puis relance."
  exit 1
fi
mkdir -p /etc/ssh/sshd_config.d
if sshd -T | grep -E '^(passwordauthentication|permitrootlogin|kbdinteractiveauthentication) yes' >/dev/null; then
  printf '%s\n' \
    '# Posé par serveur/scripts/harden-host.sh. Le premier fichier lu gagne : garde ce nom.' \
    'PasswordAuthentication no' \
    'KbdInteractiveAuthentication no' \
    'PermitRootLogin prohibit-password' > /etc/ssh/sshd_config.d/00-serveur.conf
  sshd -t
  systemctl reload ssh 2>/dev/null || systemctl reload sshd
fi
sshd -T | grep -E '^(passwordauthentication|permitrootlogin|kbdinteractiveauthentication) '

echo "== videur"
printf '%s\n' \
  '# Posé par serveur/scripts/harden-host.sh' \
  '[sshd]' \
  'enabled = true' \
  'backend = systemd' \
  'maxretry = 5' \
  'findtime = 10m' \
  'bantime = 1h' \
  "ignoreip = 127.0.0.1/8 ::1 100.64.0.0/10 $TRUSTED_IPS" > /etc/fail2ban/jail.d/sshd.local
systemctl enable -q --now fail2ban
systemctl restart fail2ban

echo "== correctifs automatiques"
printf '%s\n' 'APT::Periodic::Update-Package-Lists "1";' 'APT::Periodic::Unattended-Upgrade "1";' \
  > /etc/apt/apt.conf.d/20auto-upgrades
systemctl enable -q --now unattended-upgrades

echo "== pare-feu"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
for p in 22 80 443; do ufw allow "$p/tcp" >/dev/null; done
if ip link show tailscale0 >/dev/null 2>&1; then
  ufw allow in on tailscale0 >/dev/null
  ufw allow 41641/udp >/dev/null
fi
for ip in $TRUSTED_IPS; do ufw allow from "$ip" >/dev/null; done
ufw --force enable >/dev/null
ufw status | sed -n 1p

echo "== filtre de conteneurs"
# Les réglages vivent dans un fichier pour que l'unité les réapplique après un redémarrage.
printf 'PUBLIC_IF="%s"\nTRUSTED_IPS="%s"\nALLOW_PORTS="%s"\n' \
  "$PUBLIC_IF" "$TRUSTED_IPS" "$ALLOW_PORTS" > "$CONF"
cat > /usr/local/sbin/serveur-firewall <<'SCRIPT'
#!/bin/sh
# Posé par serveur/scripts/harden-host.sh. Filtre ce qui vient d'internet vers les ports
# publiés par les conteneurs, que le pare-feu de l'hôte ne voit pas.
set -eu
. /etc/default/serveur-firewall
for fam in iptables ip6tables; do
  $fam -L DOCKER-USER >/dev/null 2>&1 || continue
  $fam -N SERVEUR-FILTRE 2>/dev/null || true
  $fam -F SERVEUR-FILTRE
  $fam -C DOCKER-USER -j SERVEUR-FILTRE 2>/dev/null || $fam -I DOCKER-USER 1 -j SERVEUR-FILTRE
  $fam -A SERVEUR-FILTRE ! -i "$PUBLIC_IF" -j RETURN
  $fam -A SERVEUR-FILTRE -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
  if [ "$fam" = iptables ]; then
    for ip in $TRUSTED_IPS; do $fam -A SERVEUR-FILTRE -s "$ip" -j RETURN; done
  fi
  for p in 80 443 $ALLOW_PORTS; do
    $fam -A SERVEUR-FILTRE -p tcp -m conntrack --ctorigdstport "$p" -j RETURN
  done
  $fam -A SERVEUR-FILTRE -j DROP
done
SCRIPT
chmod 755 /usr/local/sbin/serveur-firewall
cat > /etc/systemd/system/serveur-firewall.service <<'UNIT'
[Unit]
Description=Filtre internet vers les ports publiés par les conteneurs
After=docker.service
PartOf=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/serveur-firewall
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target docker.service
UNIT
systemctl daemon-reload
systemctl enable -q serveur-firewall
systemctl restart serveur-firewall

echo "== terminé sur $(hostname)"
