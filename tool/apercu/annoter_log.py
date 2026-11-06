#!/usr/bin/env python3
"""Expose la fin d'un journal en annotation GitHub (journaux CI non téléchargeables)."""
from pathlib import Path
import sys

fichier = Path(sys.argv[1])
titre = sys.argv[2] if len(sys.argv) > 2 else "Journal CI"
texte = fichier.read_text(errors="replace") if fichier.exists() else "Journal absent."
texte = "\n".join(texte.splitlines()[-160:])
texte = texte.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
print(f"::error::{titre} :%0A{texte}")
