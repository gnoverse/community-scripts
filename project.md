Re @LOurs, alors en récap, les seules contraintes pour les contributeurs c'est:
- chaque personne (LOurs, gfanton, remi, etc.) se crée un sous dossier à son nom (je te laisse voir le dirtree si on les mets dans un sous-dossier tests/{gfanton,remi,etc.} ou autre)
- la seule obligation c'est dans chaque sous-dossier d'avoir un Makefile avec 4 règles `list-funding-one-shot`, `list-funding-repeatable`, `tests-one-shot`, `tests-repeatable` et 0 deps hors Makefile et Docker
- les contributeurs peuvent faire ce qu'ils veulent under the hood, utiliser n'importe quel langage, framework, cloner des repos, osef, du moment que tout est contenu dans leur image docker
- s'ils ont 0 tests-repeatable, pas de souci, leur Makefile fait juste un `echo 'no tests to run'` et voilà, pareil s'ils ont que des repeatable et pas de one-shot.
- ils peuvent ajouter des règles en plus s'ils veulent, gfanton a fait un truc beaucoup plus advanced de mémoire, du moment qu'il fournit les 4 regles de bases, il peut en ajouter 10 supplémentaires, ça servira pour les runs en local ou autre.
- chaque Makefile a une variable REMOTE, par défaut, les tests se font against 127.0.0.1:26657, mais on peut remplacer par le RPC de notre choix (il y a peut-être d'autre variables pertinentes auxquelles je pense pas)


Au root du repo, on peut créer un:
  - un dossier `funders` (ou n'importe quel autre nom qui te plait plus), dedans il y aura des scripts pour send les funds à chaque account (tu peux juste en faire un tout con pour l'instant qui send depuis test1 et le tester en local)
  - un Makefile avec la même variable `REMOTE` et deux règles:
       - make tests-one-shot FUNDER=./funders/test-13.sh
       - make tests-repeatable FUNDER=./funders/test-13.sh
   - chacune de ces règles appellent tous les sous-Makefile, passe le retour de list-funding-XXX au script funder en paramètre pour qu'il envoie les pepettes puis run les tests.


   Crée un ci.yml avec github action pour pouvoir lancés les teste sur different reseaux c est la finalité une fois que tous le reste est mit en place. 