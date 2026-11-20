# Architecture — AeroNex (projet NovaSphere)

Une application web servie en HTTPS par un Application Load Balancer, sur un groupe d'auto-scaling réparti sur deux zones de disponibilité, déployée en deux environnements (`dev`, `prod`) par Terraform et GitHub Actions dans le Learner Lab du référent AWS (`us-east-1`).

Contexte métier et équipe : voir [CADRAGE.md](CADRAGE.md). Secrets, IAM et scans : voir [SECURITE.md](SECURITE.md).

---

## 1. Schéma

```text
                    Utilisateur
                         │  https://dev.aero-nex.fr   |   https://app.aero-nex.fr
                         ▼
          DNS chez le registrar (hors AWS) : CNAME  <env>.aero-nex.fr → DNS de l'ALB
                         │                           CNAME de validation ACM (permanent)
┌────────────────────────┼──────────── VPC novasphere-<env>  10.0.0.0/16 ───────────────┐
│                        ▼                                                              │
│   ┌──────────────────────────────────────────────┐   SG alb : 80, 443 depuis Internet │
│   │ ALB novasphere-<env>-alb                     │          sortie : 80 vers SG web   │
│   │  listener :80  → redirection 301 vers :443   │                                    │
│   │  listener :443 → certificat ACM, TLS 1.3/1.2 │                                    │
│   └──────────────────────┬───────────────────────┘                                    │
│                          │ HTTP :80, target group (santé : GET / → 200)               │
│        ┌─────────────────┴──────────────────┐                                         │
│  ┌─────┴───────────────────┐   ┌────────────┴────────────┐                            │
│  │ subnet public us-east-1a│   │ subnet public us-east-1b│   sans NAT Gateway         │
│  │ 10.0.1.0/24             │   │ 10.0.2.0/24             │                            │
│  │  EC2 Debian 12 + nginx  │   │  EC2 Debian 12 + nginx  │   SG web : 80 depuis SG alb│
│  └─────────────────────────┘   └─────────────────────────┘   uniquement, pas de SSH   │
│        └──────── ASG novasphere-<env>-web-asg (Launch Template, IMDSv2) ──┘           │
└───────────────────────────────────────┬───────────────────────────────────────────────┘
                                        │ au démarrage, via LabInstanceProfile
                                        ▼
                   Parameter Store  /novasphere/<env>/db_password  (SecureString)

  State Terraform : s3://novasphere-tfstate-miz
                    ├── novasphere/dev/terraform.tfstate    verrou natif S3 (use_lockfile)
                    └── novasphere/prod/terraform.tfstate

  Code :  envs/dev ─┐
                    ├─► module « pile web » github.com/ebonnard91/terraform-aws-web-stack?ref=v1.0.0
          envs/prod ┘   module VPC terraform-aws-modules/vpc/aws 6.8.0 (registre public)
```

Ce que crée chaque partie :

| Où | Ressources |
|---|---|
| `envs/<env>/network.tf` | VPC, 2 subnets publics, Internet Gateway, tables de routage (module du registre) |
| `envs/<env>/secrets.tf` | paramètre SSM `SecureString` écrit en `value_wo` |
| `envs/<env>/main.tf` | recherche de l'AMI Debian 12 officielle |
| module de l'équipe (`v1.0.0`) | certificat ACM et sa validation, SG alb, SG web, ALB, target group, listeners 80 et 443, Launch Template, ASG |

## 2. Décisions et alternatives écartées

| Sujet | Décision | Alternatives écartées et raison |
|---|---|---|
| **State** | Un bucket S3 créé à la CLI, versionné et chiffré ; verrouillage natif `use_lockfile = true` ; une clé par environnement | *Table DynamoDB* : inutile depuis le verrouillage natif S3, et ressource de plus à gérer. *Bucket créé par Terraform* : `aws_s3_bucket` refusé dans le lab, et le bucket ne peut pas porter son propre state. *State local* : impossible à partager avec la CI et l'équipe |
| **Isolation des environnements** | Deux répertoires `envs/dev` et `envs/prod`, même module au même tag ; seuls la clé du backend et les variables diffèrent | *Workspaces* : refusés par le cahier des charges ; un seul backend et un `terraform workspace select` oublié suffisent à appliquer en prod |
| **Module de l'équipe** | Dépôt Git public séparé, appelé par `?ref=v1.0.0` ; variables typées, validations (`environment`, `subnet_ids`), outputs, aucun bloc `provider` | *Chemin local* (`../../../terraform-aws-web-stack`, utilisé au début) : pas de version, dev et prod ne peuvent pas figer une version différente pendant une évolution. *Modules ALB/ASG du registre* : le cahier des charges impose un module écrit par l'équipe |
| **VPC** | Module public du registre, version exacte `6.8.0` ; 2 AZ, subnets publics, IP publique au lancement | *Contrainte `~> 6.0`* : une nouvelle version mineure peut changer le plan sans commit ; version figée (et `CKV_TF_1` documenté dans SECURITE.md). *VPC écrit à la main* : plus de code sans valeur ajoutée |
| **Pas de NAT Gateway** | Instances en subnet public, mais SG web fermé à tout sauf l'ALB | *Subnets privés + NAT* : facturée à l'heure et au Go, budget du lab. *Subnets privés + endpoints VPC* (SSM, ssmmessages, ec2messages) : facturés par endpoint et par AZ, et les dépôts Debian restent inaccessibles sans Internet |
| **Calcul** | ASG sur Launch Template, 2 instances (`desired_capacity`), `health_check_type = "ELB"`, remplacement progressif par `instance_refresh` (50 % sains minimum) | *Instances EC2 isolées* (prod du tag `fin-S7`) : pas d'auto-réparation ni de répartition. *Santé EC2* : une instance dont nginx est tombé resterait « saine » |
| **Configuration des instances** | Script `user_data` court passé par `templatefile` : installe nginx et le CLI AWS, lit le secret, écrit la page, démarre le service. Reçoit le nom de l'environnement et le chemin du paramètre, jamais la valeur | *AMI Packer* : extension à part entière, temps pris sur le socle. *Ansible* : outil de plus pour un seul service |
| **Secret applicatif** | Parameter Store `SecureString`, chemin `/novasphere/<env>/db_password`, écrit par `value_wo` depuis une variable `ephemeral` ; l'instance le lit et n'affiche que « lu depuis Parameter Store » | *Secrets Manager* : facturé par secret et par mois, rotation inutile ici. *Argument `value`* : la valeur finirait dans le state. *Secret dans le `user_data`* : visible dans la console EC2 et dans le Launch Template |
| **Accès aux instances** | Aucun port SSH, aucune paire de clés ; administration par Session Manager | *Bastion ou SSH restreint à une IP* : port ouvert et clé privée à gérer |
| **Sécurité de l'instance** | IMDSv2 obligatoire (`http_tokens = "required"`, hop limit 1), volume EBS chiffré, profil `LabInstanceProfile` | *IMDSv1* : vol des identifiants du profil par SSRF. *Rôle IAM dédié au moindre privilège* : création de rôle refusée dans le lab ; la politique idéale est écrite dans SECURITE.md |
| **Chaîne de livraison** | GitHub Actions : sur PR, gitleaks, checkov, `fmt -check`, `validate`, puis `plan` dev et prod en commentaire ; au merge, `plan -out` puis `apply` du fichier en dev, puis prod derrière l'environnement GitHub `prod` protégé ; job de dérive `plan -detailed-exitcode` déclenchable | *Apply en local* : pas de trace, plafonné par le cahier des charges. *`apply` sans fichier de plan* : peut appliquer autre chose que ce qui a été relu |
| **Identifiants de la CI** | Identifiants de session du lab dans les secrets du dépôt, renouvelés à chaque Start Lab | *Fédération OIDC* : création du fournisseur refusée dans le lab ; le modèle est écrit dans `ci_oidc_compte_classique.tf.exemple` et comparé dans SECURITE.md |

Différences dev / prod, portées uniquement par les variables :

| Variable | dev | prod |
|---|---|---|
| clé du backend | `novasphere/dev/terraform.tfstate` | `novasphere/prod/terraform.tfstate` |
| `instance_type` | `t3.micro` | `t3.small` |
| `domain_name` | `dev.aero-nex.fr` | `app.aero-nex.fr` |
| secret du dépôt | `DB_PASSWORD_DEV` | `DB_PASSWORD_PROD` |
| paramètre lu | `/novasphere/dev/db_password` | `/novasphere/prod/db_password` |

## 3. Extension choisie : HTTPS

**Ce qui est fait** : un certificat ACM public par environnement, validé par DNS ; un listener 443 sur l'ALB avec la politique `ELBSecurityPolicy-TLS13-1-2-2021-06` ; le listener 80 ne sert aucun contenu et redirige en 301 vers 443. Le TLS se termine sur l'ALB ; le trafic ALB → instances reste en HTTP à l'intérieur du VPC, limité par les Security Groups.

**Écart avec le cahier des charges** : le cahier des charges prévoit un certificat autosigné importé dans ACM, faute de domaine. L'équipe dispose du domaine `aero-nex.fr`, dont le DNS est géré chez le registrar, hors AWS. Elle a donc choisi un certificat ACM public validé par DNS :

| Option | Retenue | Raison |
|---|---|---|
| Certificat ACM public, validation DNS chez le registrar | **oui** | certificat reconnu par les navigateurs, aucune clé privée manipulée par l'équipe, entièrement géré par Terraform |
| Certificat autosigné importé (`aws acm import-certificate`) | non | avertissement du navigateur à la démonstration ; la clé privée devrait être stockée quelque part, et dans le state si elle est importée par Terraform |
| Zone hébergée Route 53 | non | facturée au mois, alors que le lab est détruit entre les sessions ; le domaine reste chez le registrar |

**Fonctionnement à chaque déploiement** :

1. Le CNAME de validation ACM est créé **une fois** chez le registrar (`terraform output acm_validation_records`). ACM réutilise le même enregistrement pour un même domaine dans un même compte : il valide aussi les certificats recréés après un `destroy`.
2. `aws_acm_certificate_validation` attend la validation (45 min maximum) avant de créer le listener 443.
3. Le CNAME `dev.aero-nex.fr` / `app.aero-nex.fr` pointe vers `terraform output alb_dns_name`.

**Limites assumées** :

- Le nom DNS de l'ALB change à chaque recréation : le CNAME applicatif doit être mis à jour chez le registrar après chaque redéploiement complet (Start Lab). Joindre l'ALB par son nom DNS AWS donne une alerte de certificat, puisque le certificat ne couvre que `<env>.aero-nex.fr`.
- Le certificat est lié au compte du référent AWS : si le suppléant redéploie dans son lab, un nouveau CNAME de validation est à créer.
