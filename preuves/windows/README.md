# Preuves de la reprise sous Windows (13/11/2026)

Ces fichiers ont été produits sur le poste Windows, à partir du dossier
remis, par redirection PowerShell des commandes psql et des requêtes
MariaDB.

## Deux versions des journaux

- `originaux_powershell/` : fichiers tels qu'écrits par PowerShell
  (UTF-16 little-endian, fins de ligne CRLF), conservés sans modification.
- fichiers à la racine de ce dossier : mêmes contenus convertis en UTF-8
  avec fins de ligne LF, pour être lisibles sur tout système.

La conversion ne modifie que l'encodage et les fins de ligne.

## Lecture

Les trois journaux de tests Silver (`metriq_tests.txt`,
`riverlane_tests.txt`, `crm_silver_tests.txt`) sont, après conversion,
identiques aux journaux macOS correspondants : les scripts SQL sont les
mêmes, leurs sorties ne contiennent ni horodatage ni identifiant
technique, et les volumes obtenus sont identiques. Cette identité est donc
attendue.

Les éléments propres au poste Windows sont :

- `crm_initial_state.txt` : comptage MariaDB avant saisie (0/0/0) ;
- `crm_after_creation.txt` : comptage MariaDB après saisie (1/2/1) ;
- `metriq_counts.txt` et `windows_replay_counts.txt` : volumes
  Bronze/Silver de la reprise ;
- `screenshots/` : connexions Airbyte du poste Windows et réconciliation ;
- les fichiers de `originaux_powershell/`, dont l'encodage UTF-16/CRLF
  est celui de la redirection PowerShell.
