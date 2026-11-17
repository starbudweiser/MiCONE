# Serveur MCP commun iCONIQ + MiCONE — part de MiCONE (17/11/2026)

**État : proposition validée le 17/11/2026 (options recommandées), aucun code encore.** Document complet (outils, flux, sécurité, questions) :
`iCONIQ/docs/MCP_PROPOSITION.md`.

## En bref

- Recommandation : **un seul serveur `iconiq-mcp`, livré dans iCONIQ.app**, qui lie `MiCONECore` comme bibliothèque.
  MiCONE n'a pas de serveur à lui ; son moteur (`Rendu`, `Detourage`, `ImageSource`) tourne dans le processus MCP,
  appli fermée, sans fenêtre.
- Outils qui reposent sur MiCONE : `icons_make` (appli ou dossier ; dossier « nuit » `#2f4f84`, icône en couleur =
  `fondDossier = "nuit"`, `grave = false`), `icons_apply_to_folder`, `icons_clear_folder_icon`, `icons_app_kit`
  (icône d'appli + icône de dossier + pose + rangement dans iCONIQ en un appel).
- **Règle universelle** (décision du 17/11/2026) : rien de personnel en dur. La couleur de dossier par défaut est un
  réglage (défaut public : bleu Finder ; « nuit » est le choix de Stéphan), comme les collections de rangement.
- La génération par IA de MiCONE (services en ligne, crédits) n'est **pas** exposée.

## Changements à faire dans MiCONE (après validation)

1. CLI : `--fond-dossier nuit|bleu|graphite|clair|#rrggbb`, `--grave` / `--sans-grave`, `--appliquer DOSSIER`
   (aujourd'hui `--fond` ne règle que le fond d'appli ; `fondDossier` et `grave` ne sont pas exposés). Remplace dès
   maintenant le script `mSOCLE/assets/make_folder_icon.swift`.
2. `Package.swift` : produit `.library(name: "MiCONECore")`, lié par iCONIQ (chemin local en dev, tag GitHub en release).
3. `MiCONECore` reste sans dépendance à l'interface ni à `UserDefaults` dans les chemins utilisés par le serveur
   (`Reglages` passé en paramètre).
4. Version de dev (`fr.stephan.micone.dev`) : n'existe pas, à créer si Stéphan l'accepte.
