#!/usr/bin/env bash
# Re-fija el toolchain a las ultimas versiones y deja el diff listo para revisar.
# Correr DELIBERADAMENTE (inicio de fase, no a mitad de sprint) y commitear rokit.toml.
set -euo pipefail

for tool in rojo-rbx/rojo UpliftGames/wally JohnnyMorganz/StyLua Kampfkarren/selene lune-org/lune; do
	echo "==> $tool"
	rokit add "$tool"
done

rokit install
echo
echo "Listo. Revisa 'git diff rokit.toml' y corre el CI antes de commitear."
