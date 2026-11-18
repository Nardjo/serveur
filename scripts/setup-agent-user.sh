#!/usr/bin/env bash
# Crée le compte que ton agent utilise : clé seulement, pas de mot de passe, pas de droits
# d'administration, propriétaire de /opt/stacks, membre du groupe du moteur de conteneurs.
# Idempotent.
#
# Usage : sudo bash setup-agent-user.sh "<clé publique>" [nom_du_compte]
#
# À savoir, et c'est dit franchement : appartenir au groupe du moteur de conteneurs revient
# à pouvoir tout faire sur la machine. Ce compte n'est pas une prison, c'est une limite de
# dégâts — pas de mot de passe, une seule clé, et tu la retires en une ligne.
set -euo pipefail

KEY=${1:?clé publique requise}
USER_NAME=${2:-agent}
[ "$(id -u)" -eq 0 ] || { echo "à lancer en administrateur (sudo)"; exit 1; }

id "$USER_NAME" >/dev/null 2>&1 || useradd -m -s /bin/bash "$USER_NAME"
if getent group docker >/dev/null; then
  usermod -aG docker "$USER_NAME"
else
  echo "ATTENTION : le groupe docker n'existe pas, le compte ne pourra pas lancer de conteneur."
  echo "Installe le moteur de conteneurs (scripts/install.sh), puis relance ce script."
  MANQUE_DOCKER=1
fi
passwd -l "$USER_NAME" >/dev/null

HOME_DIR=$(getent passwd "$USER_NAME" | cut -d: -f6)
install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR/.ssh"
touch "$HOME_DIR/.ssh/authorized_keys"
grep -qxF "$KEY" "$HOME_DIR/.ssh/authorized_keys" || echo "$KEY" >> "$HOME_DIR/.ssh/authorized_keys"
chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.ssh/authorized_keys"
chmod 600 "$HOME_DIR/.ssh/authorized_keys"
install -d -m 755 -o "$USER_NAME" -g "$USER_NAME" /opt/stacks

# Si le service d'accès limite la liste des comptes autorisés, on ajoute celui-ci, on teste,
# et on remet tout comme avant si le test échoue.
changed=()
for f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
  [ -f "$f" ] || continue
  grep -qE '^\s*AllowUsers' "$f" || continue
  grep -qE "^\s*AllowUsers.*\b$USER_NAME\b" "$f" && continue
  cp -p "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
  sed -i -E "s/^(\s*AllowUsers.*)$/\1 $USER_NAME/" "$f"
  changed+=("$f")
done
if [ ${#changed[@]} -gt 0 ]; then
  if sshd -t; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd
    echo "comptes autorisés mis à jour : ${changed[*]}"
  else
    for f in "${changed[@]}"; do cp -p "$(ls -t "$f".bak.* | head -1)" "$f"; done
    echo "configuration refusée, changement annulé"; exit 1
  fi
fi

if [ "${MANQUE_DOCKER:-0}" = 1 ]; then
  echo "compte créé sur $(hostname), mais INCOMPLET : $(id "$USER_NAME")"
else
  echo "compte prêt sur $(hostname) : $(id "$USER_NAME")"
fi
echo
echo "Ajoute ceci dans ~/.ssh/config sur ton poste :"
echo
echo "  Host mon-serveur"
echo "    HostName <adresse>"
echo "    User $USER_NAME"
echo "    IdentityFile ~/.ssh/agent"
echo
echo "Puis vérifie :  ssh mon-serveur docker ps"
