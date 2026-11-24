# iiGameStudio

Les jeux du studio qui n'existe pas. Store de jeux web, installable en PWA.

- `/` : le store (accueil, fiches des jeux, installation, confidentialité)
- `/ntd/` : Nine Tiles Dungeon, installable seul
- `/slime/` : Slime Vertical, installable seul

Site statique, sans étape de build. Hébergé sur Vercel.

Mise à jour d'un jeu : remplacer son `index.html`, puis changer `VERSION` dans son `sw.js` pour que les joueurs reçoivent la nouvelle version.
