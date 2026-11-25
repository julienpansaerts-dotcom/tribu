# Tribu

Application iOS privée de pilotage familial : courses, menus, agenda, rappels, tâches, dépenses et
toutes les infos utiles de chacun (tailles, pointures, allergies…), partagées en temps réel.

- Cahier des charges : [SPEC.md](SPEC.md)
- Maquettes : https://claude.ai/artifact/PSTtMDCDCteqgZiYp3GfWY

## Compiler sans Xcode

Le projet Xcode n'est pas versionné : il est généré par [XcodeGen](https://github.com/yonaskolb/XcodeGen)
à partir de `project.yml`. À chaque envoi sur GitHub, l'action **iOS** compile l'app sur un Mac
de GitHub et publie des captures d'écran du simulateur (onglet *Actions* → dernière exécution →
*captures-ecran*).

Sur un Mac avec Xcode :

```bash
brew install xcodegen
xcodegen generate
open Tribu.xcodeproj
```

## Polices

Bricolage Grotesque, Caveat, Newsreader, Hanken Grotesk et Familjen Grotesk, sous licence SIL Open
Font License 1.1 (voir `Tribu/Resources/Fonts/Licenses`). Les fichiers inclus sont des instances
statiques renommées « Tribu… », générées à partir des polices variables de Google Fonts.
