# iiGameStudio

Les jeux du studio qui n'existe pas. Store de jeux web, installable en PWA.

- `/` : le store (accueil, fiches des jeux, installation, confidentialité)
- `/ntd/` : Nine Tiles Dungeon, installable seul
- `/slime/` : Slime Vertical, installable seul

Site statique, sans étape de build. Hébergé sur Vercel.

Mise à jour d'un jeu : remplacer son `index.html`, puis changer `VERSION` dans son `sw.js` pour que les joueurs reçoivent la nouvelle version.

## À chaque mise à jour (store ou jeu)

1. Changer `VERSION` dans le `sw.js` concerné (`/sw.js` pour le store, `/ntd/sw.js`, `/slime/sw.js`) : `store-v17` devient `store-v18`, etc.
2. Ajouter une entrée **en tête** de `changelog.json`, avec le même numéro :
   `{"app": "slime", "v": 7, "date": "2026-11-27T10:00", "notes": ["Ce qui change, en une phrase pour les joueurs."]}`
   `app` vaut `store`, `ntd` ou `slime`. La page Nouveautés du store, la version dans la fiche du jeu et celle du bas de page se mettent à jour toutes seules.
