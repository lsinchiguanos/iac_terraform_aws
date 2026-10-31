# deuna-transactional-platform · core-data

Provisiona en AWS la llave KMS, el bucket de registros transaccionales, el clúster Aurora PostgreSQL `transactions` y el secreto del usuario `pgadmin` con rotación automática, para las cuentas `dev` y `prod` de Deuna!.

## Recursos por ambiente

| Recurso | `prod` | `dev` |
|---|---|---|
| Llave KMS | `alias/deuna-prod-data-at-rest` | `alias/deuna-dev-data-at-rest` |
| Bucket S3 | `deuna-prod-transaction-records-891377129462` | `deuna-dev-transaction-records-730335476193` |
| Clúster Aurora | `deuna-prod-aurora-transactions` (2 × `db.r7g.large`) | `deuna-dev-aurora-transactions` (1 × `db.serverless`, 0–4 ACU) |
| Secreto | `deuna/prod/aurora-transactions/pgadmin` | `deuna/dev/aurora-transactions/pgadmin` |
| Lambda de rotación | `deuna-prod-pgadmin-rotation` | `deuna-dev-pgadmin-rotation` |
| Bucket de estado | `deuna-prod-terraform-state-891377129462` | `deuna-dev-terraform-state-730335476193` |
| Llave KMS de estado | `alias/deuna-prod-terraform-state` | `alias/deuna-dev-terraform-state` |

## Estructura

```
.
├── .github/workflows/
│   ├── terraform.yml                   PR: análisis estático + plan dev/prod · tag X.Y.Z: plan + apply dev → prod
│   └── terraform-apply.yml             workflow reutilizable: apply del .tfplan aprobado por ambiente
├── bootstrap/                          estado remoto de una cuenta (se aplica una vez por cuenta)
│   ├── backend.tf                      backend "s3" parcial; primer apply con backend_override.tf local
│   ├── main.tf                         módulos kms-key (deuna-<env>-terraform-state) y s3-bucket (deuna-<env>-terraform-state-<cuenta>)
│   ├── outputs.tf · providers.tf · variables.tf · versions.tf
│   └── .terraform.lock.hcl
├── modules/
│   ├── kms-key/                        aws_kms_key, aws_kms_alias, key policy por roles
│   ├── s3-bucket/                      bucket, ownership, public access block, versionado, SSE-KMS, object lock, lifecycle, bucket policy
│   ├── aurora-postgresql/              subnet group, SG + ingress, parameter group, log group, rol de Enhanced Monitoring, clúster, instancias
│   ├── secretsmanager-secret/          secreto, versión write-only, resource policy, rotación
│   └── rds-postgresql-rotation-lambda/ stack SAR de rotación, SG + reglas, VPC endpoint de Secrets Manager, log group
│       └── (cada módulo) main.tf · variables.tf · outputs.tf · versions.tf
├── stacks/
│   └── core-data/                      root module de la Tarea 3: llave, bucket, Aurora y secreto pgadmin
│       ├── versions.tf                 Terraform >= 1.11, aws ~> 6.0, random ~> 3.7, backend "s3" parcial
│       ├── providers.tf                provider aws con allowed_account_ids
│       ├── data.tf                     VPC, subnets private-data, SG de ECS y roles IAM existentes
│       ├── locals.tf                   nombres deuna-<env>-*, tags comunes, ARNs de roles
│       ├── main.tf                     password ephemeral + llamadas a los 5 módulos
│       ├── variables.tf · outputs.tf
│       └── .terraform.lock.hcl
├── environments/
│   ├── dev/
│   │   ├── backend.hcl                 bucket, key core-data/terraform.tfstate, llave KMS, use_lockfile
│   │   ├── bootstrap.tfvars            entradas de bootstrap/
│   │   └── terraform.tfvars            entradas de stacks/core-data/ (Serverless v2, retenciones cortas)
│   └── prod/
│       ├── backend.hcl
│       ├── bootstrap.tfvars
│       └── terraform.tfvars            2 × db.r7g.large, backups 35 d, object lock 365 d
├── .tflint.hcl
├── .pre-commit-config.yaml
├── .gitignore
└── README.md
```

### Justificación

La estructura separa tres cosas que cambian a ritmos distintos y con riesgos distintos: **cómo se construye un recurso** (`modules/`), **qué se despliega junto** (`stacks/`) y **con qué valores en cada cuenta** (`environments/`). `bootstrap/` queda aparte porque crea el bucket donde viven los demás estados.

| Carpeta | Decisión | Motivo |
|---|---|---|
| `modules/` | Un módulo por recurso de la Tarea 3, más `rds-postgresql-rotation-lambda` | Cada módulo encapsula los controles obligatorios de su recurso (SSE-KMS, bucket policy, `storage_encrypted`, `block_public_policy`); quien lo instancia no puede omitirlos porque no son variables. `bootstrap/` reutiliza `kms-key` y `s3-bucket`, así el bucket de estado tiene los mismos controles que el de datos. |
| `modules/` | Sin bloques `provider` ni `backend`; `versions.tf` con rango `>= 6.0.0, < 7.0.0` | El root module decide cuenta, región y versión exacta del provider; el módulo solo declara compatibilidad. |
| `modules/` | `validation` en `tags` que exige `Environment`, `Project`, `Owner` y `Version` | El etiquetado de costos y de release no depende de que cada stack lo recuerde. |
| `modules/rds-postgresql-rotation-lambda/` | Separado de `secretsmanager-secret/` | El rol IAM de la Lambda tiene que existir antes de escribir la key policy de KMS, y el secreto necesita esa llave; en un mismo módulo se forma un ciclo. Además su ciclo de vida es distinto: versión de la app SAR y VPC endpoint. |
| `stacks/core-data/` | Un root module para los cuatro recursos, con un state propio (`core-data/terraform.tfstate`) | Llave, bucket, clúster y secreto dependen entre sí (la key policy referencia al rol de rotación, el secreto referencia al endpoint de Aurora) y se despliegan juntos. Un stack futuro, p. ej. `stacks/ecs-observability/` para la Tarea 1, tendría su propio state y un `plan` que no puede tocar Aurora. |
| `stacks/core-data/` | Archivos por responsabilidad (`data.tf`, `locals.tf`, `main.tf`) | En revisión de PR, un cambio en `data.tf` indica dependencia nueva sobre infraestructura existente y uno en `main.tf` indica recurso nuevo o modificado. |
| `environments/<env>/` | Solo `.hcl` y `.tfvars`, sin `.tf` | El mismo código pasa de `dev` a `prod`; la única diferencia entre ambientes es lo que se ve en un diff de `terraform.tfvars`. `allowed_account_ids` hace fallar el plan si se usa el `.tfvars` de un ambiente con credenciales de la otra cuenta. |
| `environments/<env>/backend.hcl` | Configuración parcial de backend fuera del código | Cada cuenta tiene su bucket y su llave KMS de estado; el mismo `versions.tf` sirve para ambas cuentas con `terraform init -backend-config`. |
| `bootstrap/` | Root module independiente con su propio state (`bootstrap/terraform.tfstate`) | Resuelve el problema de dónde guardar el estado del bucket de estado: primer apply local con `backend_override.tf` y migración al bucket recién creado. Se aplica una vez por cuenta, no en cada release. |
| `.terraform.lock.hcl` | Versionado en `stacks/core-data/` y `bootstrap/`, no en `modules/` | Los hashes del provider se fijan donde se ejecuta `apply`; CI y la máquina local usan exactamente `aws 6.71.0` y `random 3.9.1`. |
| `.github/workflows/terraform-apply.yml` | `apply` como workflow reutilizable | `dev` y `prod` ejecutan los mismos pasos; solo cambian el GitHub Environment (aprobadores, `AWS_ACCOUNT_ID`) y el `.tfplan`. |

Alternativas descartadas:

| Alternativa | Por qué no |
|---|---|
| Una carpeta `.tf` completa por ambiente (`environments/prod/main.tf`) | Duplica las llamadas a módulos; un cambio aplicado en `dev` puede no replicarse en `prod` y el diff entre ambientes deja de ser solo de valores. |
| Terraform workspaces (`terraform workspace select prod`) | Todos los workspaces comparten backend, es decir, el mismo bucket y la misma cuenta; aquí `dev` y `prod` son cuentas AWS separadas con buckets y llaves de estado distintos. |
| Terragrunt | Resuelve la duplicación de backend con una herramienta y una sintaxis adicionales; con un solo stack y dos ambientes, `-backend-config` y `-var-file` cubren el caso sin otra dependencia en el pipeline. Se reevalúa cuando haya más de 3 stacks × 3 ambientes. |
| Un solo root module con todos los recursos de la plataforma | El state crece con cada servicio, el `plan` se vuelve lento y un error en un recurso de ECS bloquea un cambio urgente en Aurora. |

## Decisiones por recurso

### a) KMS `deuna-<env>-data-at-rest`

- `SYMMETRIC_DEFAULT`, `ENCRYPT_DECRYPT`, `multi_region = false`, rotación automática cada `365` días, ventana de borrado de 30 días en `prod` y 7 en `dev`.
- La key policy no usa `arn:aws:iam::<cuenta>:root`. Cada statement nombra los roles:

| Sid | Principales | Acciones | Condición |
|---|---|---|---|
| `KeyAdministration` | `deuna-<env>-github-terraform-deployer`, `deuna-security-break-glass` | gestión (políticas, alias, rotación, borrado); sin `Encrypt`/`Decrypt` | — |
| `CryptographicUseThroughAwsServices` | deployer, rol de la Lambda de rotación, `deuna-<env>-dba-operator`, roles de tarea ECS `payments-processor` y `transaction-ledger` | `Encrypt`, `Decrypt`, `ReEncrypt*`, `GenerateDataKey*`, `DescribeKey` | `kms:ViaService` ∈ {s3, rds, secretsmanager} y `kms:CallerAccount` = cuenta |
| `GrantsForAwsResources` | mismos | `CreateGrant`, `ListGrants`, `RevokeGrant` | `kms:GrantIsForAWSResource = true` (grants de RDS y Performance Insights) |
| `CloudWatchLogsEncryption` | `logs.us-east-1.amazonaws.com` | cifrado de log groups | `kms:EncryptionContext:aws:logs:arn` limitado a `/aws/rds/cluster/deuna-<env>-aurora-transactions/*` y `/aws/lambda/deuna-<env>-pgadmin-rotation` |

  Con `ViaService`, ningún rol puede llamar `kms:Decrypt` directo con la CLI; solo descifra a través de S3, RDS o Secrets Manager.
- Una llave para los tres servicios porque los tres guardan datos del mismo dominio (transacciones) y el enunciado pide "la llave KMS creada". Separar en una llave por servicio cuesta 1 USD/mes adicional por llave y reduce el radio de impacto; el módulo ya lo permite instanciándolo de nuevo.

### b) S3 `deuna-<env>-transaction-records-<cuenta>`

- SSE-KMS con la llave anterior y **S3 Bucket Key** activo: reduce las llamadas a KMS de una por objeto a una por bucket key, que en un bucket de alto volumen es el componente variable más caro de SSE-KMS.
- `BucketOwnerEnforced` (ACLs deshabilitadas) y Block Public Access en los cuatro flags.
- Versionado habilitado. En `prod`, Object Lock `GOVERNANCE` de 365 días: ningún rol puede sobrescribir o borrar un registro dentro de ese año salvo con `s3:BypassGovernanceRetention`, que la bucket policy reserva al deployer y al break-glass. Se eligió `GOVERNANCE` y no `COMPLIANCE` porque `COMPLIANCE` no se puede revertir ni con root; el cambio a `COMPLIANCE` lo decide Cumplimiento con el plazo regulatorio firmado.
- Bucket policy:

| Sid | Efecto |
|---|---|
| `DenyInsecureTransport` | niega cualquier request sin TLS |
| `DenyTlsBelow12` | niega TLS 1.0/1.1 |
| `DenyNonKmsEncryptionHeader` | niega `PutObject` que pida `AES256` |
| `DenyForeignKmsKey` | niega `PutObject` con una llave KMS distinta a la del bucket |
| `DenyPrincipalsOutsideAccount` | niega principales de otras cuentas (excepto servicios AWS) |
| `RestrictDestructiveActionsToPrivilegedPrincipals` | `DeleteObjectVersion`, `BypassGovernanceRetention`, cambios de policy, versionado, cifrado, lifecycle, object lock y `DeleteBucket` solo para deployer y break-glass |

- Lifecycle `prod`:

| Regla | Acción |
|---|---|
| `current-versions-tiering` | STANDARD → STANDARD_IA (30 d) → GLACIER_IR (180 d) → DEEP_ARCHIVE (730 d) → expira (3650 d) |
| `noncurrent-versions-retention` | versión no actual → GLACIER_IR (30 d), expira a 365 d conservando las 5 más recientes |
| `expired-delete-markers-and-multipart-cleanup` | borra delete markers huérfanos y uploads multiparte incompletos a 7 d |

  Los saltos respetan la permanencia mínima facturable de cada clase (30 d IA, 90 d Glacier IR, 180 d Deep Archive), así ninguna transición genera cargo por borrado anticipado. `transition_default_minimum_object_size = all_storage_classes_128K` evita mover objetos menores a 128 KB, que en IA/Glacier cuestan más por el overhead por objeto que lo que ahorran.
- `dev` expira objetos a 90 días, versiones no actuales a 7 días y no usa Object Lock.

### c) Aurora PostgreSQL `deuna-<env>-aurora-transactions`

- Aurora PostgreSQL 16.6, base `transactions`, usuario maestro `pgadmin`, `storage_encrypted = true` con la llave de datos.
- Subnets resueltas por `tag:Tier = private-data` dentro de `deuna-<env>-vpc`; `publicly_accessible = false` en cada instancia.
- Security group `deuna-<env>-aurora-transactions-sg` sin reglas de egress y con ingress 5432 solo desde los SG `deuna-<env>-ecs-payments-processor-sg`, `deuna-<env>-ecs-transaction-ledger-sg`, `deuna-<env>-ecs-onboarding-sg` y el SG de la Lambda de rotación. No hay reglas por CIDR.
- Parameter group `aurora-postgresql16`: `rds.force_ssl = 1`, `ssl_min_protocol_version = TLSv1.2`, `pgaudit` (`ddl,role`) y `pg_stat_statements` precargados, log de sentencias > 1 s, conexiones, desconexiones y lock waits, `idle_in_transaction_session_timeout` de 5 min.
- Backups: retención 35 días en `prod` (máximo de Aurora) y 7 en `dev`, ventana `06:00-07:00` UTC (01:00–02:00 hora Ecuador), mantenimiento `sun:07:30-sun:08:30` UTC, `delete_automated_backups = false`, snapshot final obligatorio, `deletion_protection = true` en `prod`.
- Monitoreo: Performance Insights cifrado con la llave de datos y retención de 7 días (capa sin costo), Enhanced Monitoring cada 30 s en `prod` y 60 s en `dev`, export del log `postgresql` a `/aws/rds/cluster/deuna-<env>-aurora-transactions/postgresql` cifrado con KMS y retención de 365/30 días. El log group se crea antes que el clúster para que RDS no lo cree sin cifrado y con retención infinita; es el log group que ingiere la plataforma de observabilidad externa.
- Autenticación IAM habilitada para que los microservicios usen tokens IAM y no la credencial `pgadmin`.
- Costo:
  - `dev` usa Serverless v2 con `min_capacity = 0` y auto-pausa a los 60 min: fuera del horario laboral el cómputo cuesta 0 y solo se paga almacenamiento.
  - `prod` usa `db.r7g.large` (Graviton) writer + reader en AZs distintas; Graviton tiene menor precio por hora que la familia Intel `r6i` a igual vCPU/memoria. La base de 2 instancias es candidata a Reserved Instances de 1 año.
  - `storage_type` queda en Aurora Standard. Se cambia a `aurora-iopt1` cuando el costo de I/O en Cost Explorer supere el 25 % del gasto total del clúster.

### d) Secreto `deuna/<env>/aurora-transactions/pgadmin`

- Cifrado con la llave de datos, ventana de recuperación 30 días en `prod`.
- Contenido en el formato que exige la Lambda de rotación de AWS: `engine`, `host`, `port`, `dbname`, `username`, `password`, `dbClusterIdentifier`.
- **La contraseña nunca entra al state ni al plan**: se genera con `ephemeral "random_password"` y se escribe con los atributos write-only `master_password_wo` (clúster) y `secret_string_wo` (secreto). Para forzar una nueva contraseña desde Terraform se incrementa `pgadmin_password_version`.
- Rotación con la aplicación oficial `SecretsManagerRDSPostgreSQLRotationSingleUser` desplegada desde Serverless Application Repository dentro de las subnets `private-data`; su SG solo sale a 5432 hacia Aurora y a 443 dentro de la VPC, y se crea un VPC endpoint de Secrets Manager con policy limitada a la cuenta. `rotate_immediately = true` reemplaza en el primer apply la contraseña generada por Terraform.
  - `prod`: `cron(0 9 ? * SUN#1 *)`, primer domingo de cada mes 04:00 hora Ecuador, ventana de 2 h, fuera de la ventana de backup y mantenimiento.
  - `dev`: todos los lunes; rota más seguido para detectar fallos de la Lambda antes que en `prod`.
- Resource policy (`block_public_policy = true`):
  - `GetSecretValue`, `PutSecretValue`, `UpdateSecretVersionStage`: solo deployer, break-glass, rol de la Lambda de rotación y `deuna-<env>-dba-operator`.
  - Cambios de policy, rotación, replicación, tags y borrado: solo deployer y break-glass.
  - Los microservicios no tienen acceso a `pgadmin`.

## Etiquetado

Todos los recursos que aceptan tags llevan:

| Tag | Valor |
|---|---|
| `Name` | nombre del recurso |
| `Environment` | `dev` / `prod` |
| `Project` | `deuna-transactional-platform` |
| `Function` | rol del recurso, p. ej. `data-at-rest-encryption`, `transaction-records-storage`, `transactional-database`, `database-master-credentials`, `database-network-access` |
| `Owner` | `cloud-infrastructure` |
| `IsMonetary` | `True` si el recurso factura por sí mismo |
| `Version` | nombre del tag Git que desplegó el recurso, p. ej. `1.1.0` |

`DataClassification = Restricted` se agrega en la llave, el bucket, el clúster, las instancias y el secreto (`Confidential` en el estado).

| `IsMonetary = True` | `IsMonetary = False` |
|---|---|
| `aws_kms_key`, `aws_s3_bucket`, `aws_rds_cluster`, `aws_rds_cluster_instance`, `aws_cloudwatch_log_group`, `aws_secretsmanager_secret`, `aws_vpc_endpoint`, stack SAR de rotación (propaga a la Lambda) | `aws_security_group`, reglas de SG, `aws_db_subnet_group`, `aws_rds_cluster_parameter_group`, `aws_iam_role` |

`aws_kms_alias`, `aws_s3_bucket_policy`, `aws_s3_bucket_*_configuration`, `aws_secretsmanager_secret_version`, `aws_secretsmanager_secret_policy` y `aws_secretsmanager_secret_rotation` no admiten tags en la API de AWS.

`Environment`, `Project`, `Owner` y `Version` se pasan como `tags` a cada módulo y cada módulo valida su presencia. `Version` sale de la variable `release_version`, que el pipeline llena con `GITHUB_REF_NAME`; no está en ningún `.tfvars`. El stack SAR de rotación propaga `Version` a la Lambda y a su rol IAM. `Name`, `Function` e `IsMonetary` los define el módulo por recurso. Para que `IsMonetary` y `Function` sirvan en Cost Explorer hay que activarlos como *cost allocation tags* en la cuenta de pagos.

## Estado remoto

- Un bucket de estado por cuenta (`deuna-<env>-terraform-state-<cuenta>`), creado por `bootstrap/` con el mismo módulo `s3-bucket`: SSE-KMS con llave dedicada `deuna-<env>-terraform-state`, versionado, versiones no actuales retenidas 365 días en `prod`, TLS obligatorio y borrado de versiones solo para deployer y break-glass.
- Bloqueo con `use_lockfile = true` (lock nativo de S3, Terraform ≥ 1.10). No se crea tabla DynamoDB: un recurso y una superficie IAM menos.
- Llaves de estado: `core-data/terraform.tfstate` para el stack y `bootstrap/terraform.tfstate` para el bootstrap, en el mismo bucket.
- El state no contiene la contraseña de `pgadmin` (write-only + ephemeral); aun así se cifra con una llave distinta a la de datos para que un rol con acceso a datos no lea el state y viceversa.

### Primer despliegue de una cuenta

```bash
cd bootstrap
printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf
terraform init
terraform apply -var-file=../environments/prod/bootstrap.tfvars -var="release_version=1.0.0"
rm backend_override.tf
terraform init -migrate-state \
  -backend-config=../environments/prod/backend.hcl \
  -backend-config="key=bootstrap/terraform.tfstate"
```

### Stack `core-data`

```bash
terraform -chdir=stacks/core-data init -reconfigure -backend-config=../../environments/prod/backend.hcl
terraform -chdir=stacks/core-data plan  -var-file=../../environments/prod/terraform.tfvars -var="release_version=1.1.0" -out=core-data-prod.tfplan
```

`-reconfigure` es obligatorio al cambiar de ambiente en la misma máquina porque `stacks/core-data/.terraform` es compartido. El `apply` local queda reservado al rol break-glass; el camino normal es el pipeline.

## Flujo de despliegue

| Evento | `dev` | `prod` | `Version` |
|---|---|---|---|
| Pull request a `master` | plan | plan | `0.0.0-pr.<n>` (solo plan, nunca se aplica) |
| Tag `X.Y.Z-rc.N` sobre `master` | plan + apply | — | `X.Y.Z-rc.N` |
| Tag `X.Y.Z` sobre `master` | plan + apply | plan + apply con aprobación | `X.Y.Z` |
| Push a `master` sin tag | — | — | — |

```bash
git checkout master && git pull
git tag -a 1.1.0 -m "core-data 1.1.0"
git push origin 1.1.0
```

- El job `release` falla si el commit del tag no es ancestro de `origin/master`; un tag creado sobre una rama de feature no despliega.
- Un tag `X.Y.Z` aplica primero en `dev` y solo si termina bien pasa a `prod`; ambos ambientes quedan con el mismo `Version`.
- Los dos planes se generan al inicio del run y el `apply` usa ese `.tfplan` exacto. Si `prod` espera la aprobación mientras alguien cambia el state, Terraform rechaza el plan como *stale* y hay que relanzar el run.
- Cada release cambia el tag `Version` de todos los recursos, por lo que el plan de un release siempre muestra actualizaciones *in-place* de tags en cada recurso. Ninguna de estas actualizaciones reemplaza ni reinicia recursos; cualquier línea `must be replaced` en el plan de `prod` es motivo para rechazar la aprobación.

Configuración en GitHub:

| Elemento | Valor |
|---|---|
| Environment `prod` | revisores obligatorios: `cloud-infrastructure`; *deployment tags* `[0-9]*.[0-9]*.[0-9]*` |
| Environment `dev` | *deployment tags* `[0-9]*.[0-9]*.[0-9]*` |
| Environments `dev-plan`, `prod-plan` | variable `AWS_ACCOUNT_ID`; sin revisores |
| Ruleset de tags | creación, borrado y actualización de tags `[0-9]*.[0-9]*.[0-9]*` restringida a `cloud-infrastructure` |
| Ruleset de `master` | PR obligatorio con check `static-analysis` y `plan` en verde |

El ruleset de tags impide mover un tag ya desplegado: `1.1.0` siempre identifica el mismo commit y el mismo valor de `Version` en AWS.

## Validación antes del `apply`

Orden de ejecución: `pre-commit` en la máquina del ingeniero → job `static-analysis` → job `plan` → aprobación del Environment `prod` → `apply` del `.tfplan` aprobado.

| Herramienta | Dónde corre | Qué detiene en este repositorio | Por qué se aplicó | Mejora |
|---|---|---|---|---|
| `terraform validate` + bloques `validation` | pre-commit, `static-analysis` | `release_version` fuera de SemVer, `account_id` que no tiene 12 dígitos, `tags` sin `Environment`/`Project`/`Owner`/`Version`, `object_lock.mode` distinto de `GOVERNANCE`/`COMPLIANCE`, retención de backups fuera de 1–35 días | Un error de tipo o de valor se detecta sin credenciales AWS y antes de llegar al plan; los `validation` codifican las reglas del equipo dentro de los módulos | Agregar `terraform test` con `mock_provider "aws"` que verifique que la key policy no contiene `arn:aws:iam::<cuenta>:root`, que la bucket policy incluye `DenyInsecureTransport` y que todo recurso con tags tiene `Version` |
| `tflint` + `tflint-ruleset-aws` 0.32.0 | pre-commit, `static-analysis` | variables, locals y `data` sources declarados y no usados, `required_providers` sin restricción de versión, nombres fuera de `snake_case`, valores de atributos AWS fuera de los enumerados de la API | `terraform validate` solo revisa el esquema del provider y acepta cualquier string; las reglas del ruleset AWS se generan desde el SDK y detectan valores que la API rechazaría a mitad del `apply`, después de haber creado parte de los recursos | Activar la regla `aws_resource_missing_tags` con `tags = ["Name", "Environment", "Project", "Function", "Owner", "IsMonetary", "Version"]` para que el etiquetado obligatorio se verifique también en recursos agregados fuera de los módulos |
| `trivy config` (severidad HIGH y CRITICAL, `exit-code 1`) | pre-commit, `static-analysis` | bucket sin SSE-KMS o sin Block Public Access, SG con `0.0.0.0/0`, Aurora sin `storage_encrypted`, log groups sin KMS, llave KMS sin rotación | Reemplaza a `tfsec` (integrado en trivy) y es la verificación más rápida de configuraciones inseguras sobre el HCL; corta el PR antes de pedir credenciales para el plan | Publicar el resultado en formato SARIF a GitHub Code Scanning para que los hallazgos queden en la pestaña Security con historial, y llevar las excepciones aceptadas en `.trivyignore` con fecha de expiración y ticket |
| `checkov` sobre el código | pre-commit, `static-analysis` | controles CIS AWS y AWS Foundational Security Best Practices sobre S3, RDS, KMS, Secrets Manager e IAM | Su base de reglas no es la misma que la de trivy y evalúa relaciones entre recursos (checks `CKV2_*` sobre el grafo), p. ej. que `aws_s3_bucket` tenga asociado su `aws_s3_bucket_public_access_block` o que `aws_secretsmanager_secret` tenga una `aws_secretsmanager_secret_rotation` | Escribir políticas propias en YAML para reglas de Deuna!: `IsMonetary` solo `True`/`False`, `DataClassification = Restricted` en recursos con datos transaccionales, secreto de Secrets Manager siempre con `aws_secretsmanager_secret_policy` |
| `checkov` sobre `terraform show -json` | job `plan` | los mismos controles con valores resueltos: ARNs de roles en la key policy, IDs reales de SG en las reglas de ingress, subnets resueltas por `tag:Tier` | En el código, la VPC, las subnets, los SG de ECS y los roles IAM vienen de `data` sources; su valor real solo existe en el plan, y ahí se verifica que ningún ingress apunte a un SG o CIDR no esperado | Agregar `conftest` con políticas OPA sobre el mismo JSON que rechacen en `prod` cualquier `delete` o `replace` sobre `aws_rds_cluster`, `aws_kms_key`, `aws_s3_bucket` y `aws_secretsmanager_secret`; hoy esa revisión depende del aprobador |
| `gitleaks` | pre-commit, `static-analysis` | access keys, contraseñas o connection strings de Aurora en commits | El repositorio maneja la credencial de `pgadmin`; aunque Terraform la genera como `ephemeral`, un `terraform.tfvars` local o un `override.tf` con contraseña podría terminar en un commit | Activar *push protection* de GitHub Secret Scanning en la organización para bloquear el `git push` en el servidor, no solo en el pre-commit que el ingeniero puede saltarse con `--no-verify` |
| job `release` | inicio de cada run | tags que no apuntan a un commit de `master` y tags con formato distinto a `X.Y.Z` / `X.Y.Z-rc.N` | Garantiza que lo que llega a `prod` pasó por PR, revisión y checks de `master`, y que el valor del tag `Version` en AWS es trazable a un commit | Exigir tags firmados (`git tag -s`) y verificar la firma en el job antes de desplegar |
| GitHub Environment `prod` con revisores obligatorios | antes del `apply` en `prod` | `apply` sin aprobación de `cloud-infrastructure`; `apply` de un plan distinto al revisado | El `apply` usa el `.tfplan` del mismo run, así el aprobador ve exactamente lo que se ejecuta; separación de funciones exigida para cambios en infraestructura de datos financieros | Publicar el resumen del plan (`terraform show -no-color`) como comentario del run o en el Job Summary para que el aprobador no tenga que descargar el artefacto |
| OIDC a `deuna-<env>-github-terraform-deployer` | jobs `plan` y `apply` | uso de access keys de larga duración en GitHub | Credenciales temporales por run, sin secretos rotables guardados en GitHub | Restringir la trust policy del rol de `prod` a `token.actions.githubusercontent.com:sub = repo:<org>/iac_terraform_aws:environment:prod` y usar un rol de solo lectura distinto para el job `plan` |

`AWS_ACCOUNT_ID` se define como variable de cada GitHub Environment.

## Prerrequisitos en cada cuenta

| Elemento | `prod` | `dev` |
|---|---|---|
| Account ID | `891377129462` | `730335476193` |
| VPC (`tag:Name`) | `deuna-prod-vpc` | `deuna-dev-vpc` |
| Subnets de datos (`tag:Tier`) | `private-data`, ≥ 2 AZ | `private-data`, ≥ 2 AZ |
| Rol de despliegue (OIDC GitHub) | `deuna-prod-github-terraform-deployer` | `deuna-dev-github-terraform-deployer` |
| Rol break-glass | `deuna-security-break-glass` | `deuna-security-break-glass` |
| Rol DBA | `deuna-prod-dba-operator` | `deuna-dev-dba-operator` |
| Roles de tarea ECS con escritura al bucket | `deuna-prod-ecs-payments-processor-task`, `deuna-prod-ecs-transaction-ledger-task` | `deuna-dev-ecs-payments-processor-task`, `deuna-dev-ecs-transaction-ledger-task` |
| SG de clientes de Aurora | `deuna-prod-ecs-payments-processor-sg`, `deuna-prod-ecs-transaction-ledger-sg`, `deuna-prod-ecs-onboarding-sg` | equivalentes `deuna-dev-*` |

Si la VPC ya tiene un endpoint de Secrets Manager con DNS privado, se pone `create_secretsmanager_vpc_endpoint = false` en `rotation_lambda`; dos endpoints con DNS privado para el mismo servicio no pueden coexistir en una VPC. La versión de la app SAR se fija en `rotation_lambda.application_version` con el valor de `aws serverlessrepo list-application-versions --application-id arn:aws:serverlessrepo:us-east-1:297356227824:applications/SecretsManagerRDSPostgreSQLRotationSingleUser`.
