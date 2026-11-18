# Sécurité — AeroNex (projet NovaSphere)

Ce document décrit où vivent les secrets du projet, comment la chaîne de livraison les protège, et comment les résultats des scans de sécurité sont traités. Il répond à l'exigence « Sécurité » du cahier des charges (section 2) et à la composante E de la notation.

> **État du document** : la section 1 (sécurité des pipelines) est complète. Les sections 2 à 4 sont à compléter au fil du projet (marquées *à compléter*).

---

## 1. Sécurité de la chaîne de livraison (GitHub Actions)

### 1.1 Vue d'ensemble

Deux workflows portent la chaîne. Chaque contrôle de sécurité est placé **avant** toute action qui touche AWS.

```text
Pull request vers main  ──►  terraform-pr.yml
   ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐
   │ gitleaks     │  │ checkov      │  │ fmt + validate   │   en parallèle,
   │ (secrets)    │  │ (scan IaC)   │  │ (dev, prod)      │   sans identifiants AWS
   └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘
          └─────────────────┼───────────────────┘
                            ▼  les trois doivent réussir
                 ┌─────────────────────┐
                 │ plan (dev, prod)    │   seul job qui reçoit les identifiants AWS
                 │ → commentaire PR    │
                 └─────────────────────┘

Merge sur main  ──►  terraform-apply.yml
   apply-dev (plan -out puis apply du fichier)
        │
        ▼  approbation d'un relecteur requis (environnement GitHub "prod")
   apply-prod (plan -out puis apply du fichier)
```

| Contrôle | Où | Ce qu'il empêche | Bloquant |
|---|---|---|---|
| gitleaks | `terraform-pr.yml`, job `gitleaks` | un secret commité dans le code ou l'historique | oui |
| checkov | `terraform-pr.yml`, job `checkov` | une ressource AWS mal configurée (SG ouvert, IMDSv1, chiffrement absent…) | oui |
| `fmt -check` / `validate` | `terraform-pr.yml`, job `fmt-validate` | du code mal formé ou invalide qui arrive jusqu'au plan | oui |
| Ordre des jobs (`needs:`) | `terraform-pr.yml`, job `plan` | que du code non vérifié s'exécute avec les identifiants AWS | — |
| Permissions minimales | les deux workflows | qu'un job compromis écrive dans le dépôt | — |
| Environnement `prod` protégé | `terraform-apply.yml`, job `apply-prod` | un déploiement en prod sans relecture humaine | oui |
| Protection de `main` | réglages du dépôt | un merge sans PR, sans relecture ou avec des checks en échec | oui |

### 1.2 gitleaks : détection de secrets

- **Quand** : sur chaque pull request vers `main`.
- **Quoi** : l'action `gitleaks/gitleaks-action@v2` analyse **chaque commit de la PR**, et pas seulement l'état final des fichiers. Le checkout se fait avec `fetch-depth: 0` pour disposer de l'historique.
- **Pourquoi l'historique** : un secret commité puis supprimé dans un commit suivant reste lisible dans Git. Le cahier des charges interdit un secret dans « l'historique Git », pas seulement dans le code.
- **Ce qui est détecté** : clés AWS (`AKIA…`, `ASIA…`), jetons de session, clés privées, mots de passe dans des chaînes de connexion, et les autres motifs de la configuration par défaut de gitleaks.

**Si gitleaks échoue**, la PR ne peut pas être mergée. La procédure :

1. **Considérer le secret comme compromis**, même si la PR n'est pas mergée : le dépôt est public, et le commit est visible dès qu'il est poussé.
2. **Révoquer ou changer le secret** :
   - identifiants du Learner Lab : *End Lab* puis *Start Lab* pour en obtenir de nouveaux, puis mettre à jour les secrets du dépôt ;
   - mot de passe applicatif : changer `DB_PASSWORD_<ENV>` et incrémenter `value_wo_version` dans `secrets.tf`.
3. **Retirer le secret de l'historique** de la branche (réécriture puis `git push --force` sur la branche de travail, jamais sur `main`). C'est l'étape 2 qui protège réellement : un secret publié est réputé connu.

Un faux positif se documente ici, dans la section 3, et s'ignore par un fichier `.gitleaksignore` contenant l'empreinte (*fingerprint*) donnée par gitleaks, jamais en désactivant le job.

### 1.3 checkov : analyse statique du code Terraform

- **Quand** : sur chaque pull request vers `main`.
- **Quoi** : l'action `bridgecrewio/checkov-action@v12` scanne le répertoire `envs/` avec le framework `terraform`.
- **Module de l'équipe inclus** : `download_external_modules: true` fait télécharger et analyser le module appelé par `?ref=vX.Y.Z`. C'est là que se trouvent les Security Groups, le Launch Template et l'ALB, donc l'essentiel des contrôles.
- **Bloquant** : `soft_fail` reste à sa valeur par défaut, `false`. Une règle en échec bloque la PR.

**Traiter un résultat** : deux issues seulement.

1. **Corriger** le code (cas par défaut).
2. **Accepter l'écart**, quand la correction est impossible dans le Learner Lab ou inutile pour le projet. On l'ignore alors **dans le code**, sur la ressource concernée, avec une justification :

   ```hcl
   resource "aws_lb" "this" {
     #checkov:skip=CKV2_AWS_28:Pas de WAF dans le périmètre du projet (coût, Learner Lab)
     ...
   }
   ```

   Puis on reporte l'écart dans le tableau de la section 3. Un `skip` sans ligne dans ce tableau n'est pas accepté en relecture de PR.

### 1.4 Format et validation

`terraform fmt -check` et `terraform validate` tournent sur `envs/dev` et `envs/prod`, avec `init -backend=false`. Ce job **ne reçoit aucun identifiant AWS** : il vérifie la forme du code sans pouvoir toucher à l'infrastructure ni au state.

### 1.5 Ordre des jobs : rien ne touche AWS avant les contrôles

Le job `plan` déclare `needs: [gitleaks, checkov, fmt-validate]`. Les identifiants AWS et les mots de passe ne sont injectés que dans ce job. Conséquence : du code qui contient un secret, une ressource dangereuse ou une erreur de syntaxe n'est jamais exécuté avec les droits du Learner Lab.

### 1.6 Gestion des secrets dans la CI

| Secret | Stockage | Utilisé par | Renouvellement |
|---|---|---|---|
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` | secrets du dépôt | jobs `plan`, `apply-dev`, `apply-prod` | à chaque *Start Lab* (validité 4 h), par le référent AWS |
| `DB_PASSWORD_DEV` | secret du dépôt | `plan (dev)`, `apply-dev` | changement manuel + `value_wo_version` |
| `DB_PASSWORD_PROD` | secret du dépôt | `plan (prod)`, `apply-prod` | idem |
| `OWNER` | **variable** du dépôt (pas un secret) | tous les jobs Terraform | — |

Comment un secret traverse la chaîne sans jamais être écrit :

1. GitHub injecte le secret dans la variable d'environnement `TF_VAR_db_password` du job. Sa valeur est **masquée** (`***`) dans les logs.
2. Terraform le reçoit dans la variable `db_password`, déclarée `ephemeral = true` : elle n'est écrite **ni dans le plan, ni dans le state**.
3. La ressource `aws_ssm_parameter` l'écrit dans Parameter Store via l'argument en écriture seule `value_wo` : la valeur n'est **jamais stockée dans le state**.
4. L'instance la lit au démarrage dans Parameter Store grâce à son profil IAM. Elle ne transite par aucun fichier du dépôt.

**Un secret par environnement, sans repli** : le job de plan choisit le secret par son nom, `secrets[format('DB_PASSWORD_{0}', matrix.env)]`. Si `DB_PASSWORD_PROD` manque, la valeur est vide et le plan échoue. La prod ne reçoit jamais le mot de passe de dev par erreur.

**Pas de `terraform.tfvars` en CI** : les valeurs passent par des variables `TF_VAR_*`. Le fichier `terraform.tfvars` est exclu par `.gitignore` ; seul `terraform.tfvars.example`, sans aucune valeur sensible, est versionné.

### 1.7 Permissions minimales des workflows

| Workflow | Permissions du `GITHUB_TOKEN` | Pourquoi |
|---|---|---|
| `terraform-pr.yml` | `contents: read`, `pull-requests: write` | lire le code ; poster le plan en commentaire |
| `terraform-apply.yml` | `contents: read` | lire le code, rien d'autre |

Règles complémentaires, issues du cahier des charges (section 8) :

- **Jamais de `pull_request_target`**. Ce déclencheur exécute le workflow avec les secrets du dépôt, même pour une PR venant d'un fork : n'importe qui pourrait les exfiltrer.
- **Pas de fork** : l'équipe travaille par branches dans le dépôt. Une PR ouverte depuis un fork ne reçoit aucun secret, donc son plan échoue, ce qui est le comportement voulu.
- **Collaborateurs limités** aux membres de l'équipe et à l'intervenant. Tout collaborateur peut lire les identifiants AWS en modifiant un workflow dans sa branche : l'accès en écriture au dépôt équivaut à l'accès au Learner Lab.

### 1.8 Protection du déploiement en production

L'environnement GitHub `prod` est configuré ainsi (Settings → Environments → prod) :

| Réglage | Valeur | Effet |
|---|---|---|
| Required reviewers | les autres membres de l'équipe | `apply-prod` attend une approbation |
| Prevent self-review | coché | la personne qui a mergé ne peut pas approuver son propre déploiement |
| Allow administrators to bypass | décoché | le propriétaire du dépôt est soumis à la même règle |
| Deployment branches | `main` uniquement | aucune autre branche ne peut déployer en prod |

`apply-prod` dépend de `apply-dev` (`needs:`) : la prod n'est déployée que si le même code s'est appliqué sans erreur en dev.

**Apply à partir du fichier de plan** : chaque job d'apply exécute `terraform plan -out=tfplan` puis `terraform apply tfplan`. L'apply exécute exactement les changements que le plan a affichés dans les logs, sans recalcul.

### 1.9 Protection de la branche `main`

Réglée dans Settings → Branches :

- pull request obligatoire avec **une approbation** (GitHub interdit d'approuver sa propre PR) ;
- approbations annulées par un nouveau push ;
- checks obligatoires : `Secrets (gitleaks)`, `Scan IaC (checkov)`, `fmt et validate (dev|prod)`, `plan (dev|prod)` ;
- pas de force-push, pas de suppression ;
- règle appliquée aussi aux administrateurs.

### 1.10 Accès concurrent au state

Le backend S3 utilise le verrouillage natif (`use_lockfile = true`). Tous les `plan` et `apply` de la CI attendent la libération du verrou jusqu'à 5 minutes (`-lock-timeout=5m`) au lieu d'échouer immédiatement. Les jobs d'apply d'un même environnement sont en plus sérialisés par un groupe `concurrency` GitHub (`tfstate-dev`, `tfstate-prod`).

### 1.11 Limites connues et écarts assumés

| Limite | Risque | Traitement |
|---|---|---|
| Identifiants AWS statiques dans les secrets du dépôt, au lieu d'une fédération OIDC | une fuite donne accès au lab jusqu'à expiration (4 h max) | imposé par le Learner Lab (création de fournisseur OIDC refusée). Le modèle cible est écrit dans `envs/*/ci_oidc_compte_classique.tf.exemple` (voir section 4) |
| Plan publié en commentaire d'une PR sur un dépôt public | expose la structure de l'infrastructure (noms, ARN, CIDR), pas de secret : `db_password` est éphémère et `value_wo` n'apparaît pas dans le plan | accepté : exigé par le cahier des charges, infrastructure détruite entre les sessions |
| Actions tierces référencées par tag majeur (`@v4`), pas par empreinte SHA | un tag déplacé par l'éditeur de l'action change le code exécuté | accepté pour la lisibilité ; actions officielles ou très répandues uniquement |
| L'approbation prod est donnée avant le calcul du plan prod | le relecteur approuve sur la base du plan de la PR, pas du plan au moment du déploiement | accepté : `apply-dev` a validé le même code juste avant ; amélioration possible : job `plan-prod` séparé, plan transmis en artefact |
| Pas de scan sur `push` vers `main` | — | la protection de `main` rend impossible un merge qui n'a pas passé gitleaks et checkov en PR |

### 1.12 Vérifications à montrer au jury

```bash
# Le mot de passe n'est pas dans le state (aucun résultat attendu)
terraform state pull | grep -i -E "password|value_wo"

# Le secret existe dans Parameter Store, chiffré, sans afficher sa valeur
aws ssm describe-parameters --parameter-filters "Key=Name,Values=/novasphere/dev/db_password"

# Aucun secret dans l'historique Git, en local
gitleaks git --verbose .
```

---

## 2. Les secrets et où ils vivent

*À compléter* : inventaire complet (Parameter Store `/novasphere/<env>/…`, secrets GitHub, ce qui n'est pas un secret, comme le nom de l'environnement passé par `templatefile`), et preuve de lecture par l'instance sans affichage de la valeur.

## 3. Résultats des scans et traitement

*À compléter après le premier run sur le code complet.*

| Outil | Règle | Ressource | Décision (corrigé / accepté) | Justification |
|---|---|---|---|---|
| checkov | | | | |
| gitleaks | | | | |

## 4. Politique IAM idéale de l'instance et écart OIDC

*À compléter* : politique au moindre privilège (`ssm:GetParameter` sur `/novasphere/<env>/*` uniquement, `kms:Decrypt` sur la clé utilisée), comparée à `LabInstanceProfile` imposé par le lab ; différence entre identifiants statiques du lab et rôle OIDC d'un compte classique.
