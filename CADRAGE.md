# Fiche de cadrage d'équipe (séance 8)

> *Terraform et Automatisation du déploiement d'infrastructures dans le cloud — Master SRC, Bac+5*

Une page, remise à l'intervenant avant le premier `terraform plan`, puis versionnée dans le dépôt sous `CADRAGE.md`. Elle fixe ce que l'équipe construit au-delà du socle imposé par le cahier des charges. **Une fiche non validée n'autorise pas à dépasser le socle.**

**Équipe** : Groupe 2 **Classe** : 5src 2

| Membre | Rôle (référent Git, référent AWS, autre) | Compte GitHub |
|--------|------------------------------------------|---------------|
|    Esteban Bonnard    |Référent Git|    ebonnard91           |
|   Benjamin Leberre     |Supléant git |Benjamin440|
|    Massimo Izzi    |référent AWS|Maxizzi21|
|    Quentin Gouby-Ollivier    |Supleant AWS|Quentin Da Silva|

**Learner Lab de l'équipe** (référent AWS) : Massimo Izzi **Suppléant** : Quentin Gouby-Ollivier

**Dépôts publics** : projet https://github.com/ebonnard91/projet-infrastructure-novasphere module https://github.com/ebonnard91/terraform-aws-security-group ; collaborateurs : les membres et l'intervenant, personne d'autre (ils accèdent aux secrets de la CI)

## Le contexte (quatre lignes)

*Nom de l'application, métier, ce que les instances servent (page, API, site statique), nom des environnements.*

1. **Application** : AeroNex, le site vitrine de l'entreprise industrielle AeroNex, dans le cadre de la mission 5SRC 2026-2027 (modernisation, sécurisation hybride et automatisation de son infrastructure).
2. **Métier** : présenter l'entreprise, ses activités industrielles, ses services et ses contacts aux clients, partenaires et candidats.
3. **Ce que servent les instances** : un site statique (pages HTML/CSS) servi par un serveur web sur des instances EC2, derrière un Application Load Balancer.
4. **Environnements** : `dev` pour les tests et la validation, et `prod` pour le site public. Les deux sont déployés par Terraform à partir du même code et ne diffèrent que par leurs variables.

## L'extension choisie (une seule)

- [x] HTTPS (certificat importé dans ACM, listener 443)
- [ ] Administration sans SSH (SSM Run Command, sans paire de clés)
- [ ] Base de données (RDS)
- [ ] Image préconstruite (Packer)
- [ ] Configuration par Ansible (ansible-pull ou SSM Run Command)
- [ ] Second service derrière l'ALB
- [ ] Tests de module (`terraform test`)
- [ ] Autre, à faire accepter : ______________________

**Ce qu'elle exige en plus du socle** (ressources, coût horaire, temps estimé) :

Un certificat auto-signé importé dans ACM, un listener 443 sur l'ALB avec redirection du port 80 vers HTTPS et une règle 443 dans le security group, pour un surcoût d'environ 0 $/h et environ 5 h de travail.

## Ce que l'équipe écarte, et pourquoi

L'équipe écarte le nom de domaine avec Route 53 (impossible à obtenir dans le Learner Lab) ainsi que les autres extensions comme RDS, Packer ou Ansible, inutiles pour un site vitrine statique, puisqu'une seule extension est autorisée.

## Validation

Validée par l'intervenant le ________ :

- [ ] telle quelle
- [ ] réduite à : ______________________________________________

**Signature de l'équipe** : BEQM **Signature de l'intervenant** : ______________________

---

*Hemerson KOFFI, intervenant*
