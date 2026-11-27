# Règles d'équipe

Règles de travail du Groupe 2 (5SRC 2) sur ce dépôt : celles de la séance 1, adaptées au projet et au cahier des charges. Elles s'appliquent à tous les membres, référents compris.

## 1. Rôles

| Rôle | Titulaire | Suppléant | Responsabilités |
|---|---|---|---|
| Référent Git | Esteban Bonnard | Benjamin Leberre | réglages du dépôt, protection de `main`, environnements GitHub, tags |
| Référent AWS | Massimo Izzi | Quentin Gouby-Ollivier | Learner Lab de l'équipe, bucket de state, secrets AWS du dépôt, opérations hors CI |

Si le référent AWS est absent, le suppléant crée son propre bucket, redéploie depuis le code dans son lab et remplace les secrets du dépôt par les siens.

## 2. Branches

- On travaille par branche **dans ce dépôt**, jamais par fork : un workflow lancé depuis un fork ne reçoit pas les secrets.
- Une branche part de `dev` à jour (`git fetch` puis `git switch -c <branche> origin/dev`) et traite **un seul sujet**.
- Nommage :

  | Préfixe | Usage | Exemple |
  |---|---|---|
  | `feature/` | nouvelle ressource ou fonctionnalité | `feature/pipeline-drift` |
  | `fix/` | correction | `fix/pipeline-apply` |
  | `fix/Checkov-policy-<ID>` | traitement d'une règle checkov | `fix/Checkov-policy-CKV_AWS_130` |
  | `doc/` | documentation seule | `doc/Security` |

- Circuit : `branche → dev` par pull request, puis `dev → main` par pull request. Le merge sur `main` déclenche le déploiement.

## 3. Commits

- Chacun commite **depuis son poste, sous son propre nom** (`git config user.name` / `user.email`) : la contribution de chacun est lue dans l'historique.
- Format du message : `type(portée): description`, en français, au présent.
  Types : `feat`, `fix`, `ci`, `docs`, `refactor`, `chore`. Exemple : `fix(checkov): accepte CKV_AWS_130 sur les subnets publics du VPC`.
- Un commit = un changement cohérent. Pas de commit « wip » ni « test » sur `dev` ou `main`.

## 4. Pull requests

- Toute modification de `dev` et de `main` passe par une pull request.
- **Une approbation d'un autre membre** est obligatoire. GitHub interdit d'approuver sa propre PR.
- Un nouveau push annule les approbations : on relit à nouveau.
- Pas de force-push ni de suppression de `main`. La règle s'applique aussi au propriétaire du dépôt.
- Sur une PR vers `main`, ces checks doivent être verts : `Secrets (gitleaks)`, `Scan IaC (checkov)`, `fmt et validate (dev|prod)`, `plan (dev|prod)`.
- Le relecteur **lit le plan posté en commentaire** avant d'approuver : nombre de ressources ajoutées, modifiées ou détruites, et aucune destruction inattendue.
- La description de la PR dit ce qui change, pourquoi, et comment le vérifier.

## 5. Avant de pousser

Aucun identifiant AWS n'est nécessaire en local pour ces commandes :

```bash
terraform fmt -recursive
terraform -chdir=envs/dev init -backend=false && terraform -chdir=envs/dev validate
terraform -chdir=envs/prod init -backend=false && terraform -chdir=envs/prod validate
```

Le plan, lui, est calculé par la CI et lu dans la PR. Seul le référent AWS lance un `plan` ou un `apply` en local, pour un diagnostic.

## 6. Code Terraform

- **Dev et prod ont le même code.** Seuls diffèrent la clé du backend (`backend.tf`), les valeurs des variables (`terraform.tfvars`, `TF_VAR_` des jobs de CI) et l'environnement GitHub. Une modification de `envs/dev` est reportée dans `envs/prod` dans la même PR.
- Les deux environnements appellent **le même tag** du module de l'équipe.
- Module de l'équipe : chaque évolution est publiée sous un **nouveau tag** `vX.Y.Z`. Un tag publié n'est jamais déplacé ni supprimé.
- Pas de bloc `provider` dans le module. Pas de workspace.
- Un changement fait à la main dans la console AWS est interdit. S'il a eu lieu, le job de dérive le signale, et on le corrige par le code.

## 7. Secrets

- Aucun secret dans le code, le state, le script de démarrage, l'historique Git ou les logs de CI.
- Jamais de commit de `terraform.tfvars`, `*.tfstate`, `.terraform/`, `*.pem` ou `.env` : le `.gitignore` les exclut, on ne le contourne pas (`git add -f`).
- `db_password` n'a pas de valeur par défaut. Il est fourni par `TF_VAR_db_password` depuis les secrets GitHub `DB_PASSWORD_DEV` et `DB_PASSWORD_PROD`.
- À chaque Start Lab, le référent AWS met à jour `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` et `AWS_SESSION_TOKEN` dans les secrets du dépôt.
- Workflows : `permissions:` minimales, jamais de `pull_request_target`.
- Seuls les membres de l'équipe et l'intervenant sont collaborateurs : tout collaborateur peut lire les secrets en modifiant un workflow.
- Un secret commité par erreur est **révoqué ou changé immédiatement**. Le supprimer dans un commit suivant ne suffit pas, puisqu'il reste dans l'historique.

## 8. Scans de sécurité

Chaque résultat de gitleaks ou checkov est traité de l'une des deux façons suivantes :

1. **corrigé** dans le code ;
2. **accepté** : `#checkov:skip=<ID>:<justification>` sur la ressource, **et** une ligne dans le tableau de la section 3 de `SECURITE.md`.

Un skip sans ligne dans `SECURITE.md` est refusé en relecture. On ne désactive jamais un job de scan.

## 9. Fin de session de travail

- Rien ne tourne entre deux sessions : on lance le workflow `terraform-destroy` (Actions, Run workflow) avant de quitter, et on vérifie qu'il est vert.
- Pour redéployer en début de session : Start Lab, mise à jour des secrets AWS, puis le workflow `terraform-apply` en manuel.

## 10. Reste-à-faire

Les items nominatifs de la séance 9 sont dans `RESTE_A_FAIRE.md`. Chacun coche les siens dans la PR qui les réalise.
