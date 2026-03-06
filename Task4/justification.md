# Обоснование конфигурации — Task 4

## 1. Выбор облачного провайдера: Yandex Cloud

**Yandex Cloud** выбран как основная облачная платформа по следующим причинам:

- **Юрисдикция**: Все данные (медицинские, финансовые) хранятся на территории РФ — требование 152-ФЗ и регуляторов (ЦБ, Минздрав). Yandex Cloud сертифицирован ФСТЭК.
- **Managed Services**: Полноценные управляемые сервисы (Kafka, PostgreSQL, Kubernetes) снижают операционную нагрузку на команду.
- **Terraform-провайдер**: `yandex-cloud/yandex` активно поддерживается и покрывает все необходимые ресурсы.
- **Экосистема**: Интеграция с Yandex DataLens, Yandex DataTransfer, Yandex Monitoring.

---

## 2. Выбор ресурсов и параметров

### 2.1 Сеть: VPC, подсети, NAT Gateway

| Параметр | Значение | Обоснование |
|---|---|---|
| VPC CIDR | `10.10.0.0/16` | Достаточный пул для 5 подсетей с запасом роста |
| Подсеть mgmt-a | `10.10.0.0/24` | Изолированная зона управления: только bastion и admin-инструменты |
| Подсети app-a/b | `10.10.1-2.0/24` | Разнесены по зонам A и B для HA Kubernetes нод |
| Подсети data-a/b | `10.10.3-4.0/24` | Изолированный data-tier: Kafka, PostgreSQL не смешиваются с app |
| NAT Gateway | Shared Egress | Единая точка исходящего трафика для всех приватных подсетей; без NAT ВМ без публичного IP не могут обновляться и pull образов |
| Route Table | `0.0.0.0/0 → NAT` | Все приватные подсети маршрутизируются через NAT — интернет без публичных IP |

**Зачем 5 подсетей (не одна)?**
Изоляция тиров — best practice сетевой безопасности. Security Group для PostgreSQL разрешает трафик только из app-подсетей, а не из всей VPC. Это минимизирует blast radius при компрометации одного сервиса.

---

### 2.2 Bastion Host (IaaS VM)

| Параметр | Значение | Обоснование |
|---|---|---|
| Платформа | `standard-v3` | Актуальное поколение Intel Ice Lake, лучшее соотношение цена/производительность |
| vCPU | 2 | Jump-хост не выполняет вычислительных задач, нужен только для SSH-туннелирования |
| RAM | 2 GB | Минимум для Ubuntu 22.04 + admin-утилиты |
| CPU fraction | 20% | Гарантированная доля CPU: 20% достаточно для интерактивных SSH-сессий, экономия ~60% |
| Диск | SSD 20 GB | Только ОС + утилиты (psql, kafkacat, kubectl). Данные не хранятся на bastion |
| NAT | `true` | Единственная ВМ с публичным IP; все остальные — через bastion |
| Preemptible | `true` в dev | Прерываемые ВМ дешевле на ~80%; в prod отключено для стабильности |
| OS | Ubuntu 22.04 LTS | LTS-поддержка до 2027, широкая экосистема пакетов |

---

### 2.3 Managed Kafka

| Параметр | Значение | Обоснование |
|---|---|---|
| Версия | 3.5 | Последняя стабильная версия с поддержкой KRaft и улучшенным сжатием |
| Брокеров на зону | 1 (dev) → 2 (prod) | В dev минимальная HA (1+1=2 брокера); в prod 2+2=4 для производительности |
| Preset | `s3-c2-m8` (2 vCPU/8 GB) | Достаточно для 6 топиков с нагрузкой dev; в prod переходим на `s3-c4-m16` |
| Диск | SSD 100 GB | Kafka хранит данные 7 дней; 100 GB с учётом репликации (×2) |
| ZooKeeper | `s3-c2-m8`, 20 GB | ZooKeeper — coordinator, не хранит данные, минимальный preset |
| Без публичного IP | `assign_public_ip = false` | Kafka не должна быть доступна из интернета. Только из app-подсетей |
| `min_insync_replicas` | 1 (dev) | В dev допускаем потерю одного брокера; в prod = 2 (строгая гарантия) |
| Retention | 7 дней / 5 GiB | Баланс: достаточно для replay данных при инциденте; не переполняет диск |

**Топики** разбиты по доменам с разными параметрами:
- `clinic.*` / `fintech.*` — 6 партиций (параллельная обработка нескольких потребителей)
- `ai.*` — 3 партиции (меньший throughput, тяжёлые сообщения)
- `partner.pharma.catalog` — 1 партиция, retention=-1 (каталог меняется редко, хранить вечно)

---

### 2.4 Managed PostgreSQL

#### Домен Клиники (`s3-c2-m8`, SSD 50 GB)

| Параметр | Значение | Обоснование |
|---|---|---|
| Preset | `s3-c2-m8` | Операционные данные клиники: расписание, визиты. OLTP-нагрузка умеренная |
| Диск | 50 GB SSD | Операционные данные 1–5 клиник. Медкарты хранятся в EMR (не здесь) |
| Backup | 7 дней | Стандартный период для operational DB; достаточно для point-in-time recovery |
| HA | 2 hosts (a+b) | Один хост в зоне A (primary), один в зоне B (replica) — автоматический failover |
| Без публичного IP | Да | Доступ только из приватных подсетей через Security Group |

#### Домен Финтех (`s3-c4-m16`, SSD 100 GB)

| Параметр | Значение | Обоснование |
|---|---|---|
| Preset | `s3-c4-m16` | Финансовые транзакции требуют вдвое больше ресурсов: конкурентные соединения, индексы |
| Диск | 100 GB SSD | Счета, транзакции, кредитный портфель: объём данных выше, рост предсказуем |
| Backup | 14 дней | Финансовые данные: расширенный период для compliance с нормативами ЦБ |
| HA | 2 hosts (a+b) | Аналогично клинике, с автоматическим failover |

**Почему раздельные кластеры** (не один PostgreSQL для всех доменов)?
Принцип Data Mesh: каждый домен владеет своей базой. Нагрузка на финтех-транзакции не влияет на клинический домен. Изоляция данных соответствует требованиям регуляторов.

---

### 2.5 Kubernetes (Regional HA)

| Параметр | Значение | Обоснование |
|---|---|---|
| Топология master | Regional (a+b) | Три master-ноды распределены по зонам автоматически; отказ одной зоны не роняет кластер |
| Public IP master | `false` | API server недоступен из интернета; доступ через VPN или bastion-туннель |
| Release channel | STABLE | В prod нужна предсказуемость; RAPID — для тестовых кластеров |
| General nodes | 4 vCPU / 8 GB, autoscale 1–5 | Хватает для Clinic App, Portal, Fintech API, dbt-jobs при dev-нагрузке |
| AI nodes | 8 vCPU / 32 GB, autoscale 0–3 | Scale-to-zero: нода создаётся только при наличии AI-workload, экономия |
| Disk nodes | SSD 64 GB | Container images + ephemeral storage для pods |
| Taint AI | `workload-type=ai:NoSchedule` | Предотвращает планирование non-AI workloads на дорогие AI-ноды |
| Preemptible | `true` в dev | Экономия до 80% в dev-окружении; в prod `false` |
| Auto-upgrade | Sunday 03:00, 3h window | Обновления в нерабочее время с ограниченным окном |

---

### 2.6 Object Storage (Data Lakehouse)

| Параметр | Значение | Обоснование |
|---|---|---|
| Версионирование | Включено | Защита от случайного удаления Data Products; возможность rollback трансформаций |
| SSE-KMS | Включено | Шифрование данных at-rest — требование информационной безопасности и 152-ФЗ |
| Lifecycle (COLD) | После 90 дней | Аналитические данные старше 90 дней запрашиваются редко; COLD дешевле в ~2-3 раза |
| Структура `/domains/` | clinic, fintech, ai, hq | Изоляция Data Products по доменам на уровне prefix; управление доступом через IAM |
| Service Account key | Static access key | Требуется для S3-совместимого API (dbt-spark, AWS CLI, Python boto3) |

---

## 3. Декларативный подход: почему Terraform

### 3.1 Декларативность vs. Императивность

**Императивный подход** (bash-скрипты, ручные команды):
```bash
# Создать VPC
yc vpc network create --name my-vpc
# Создать подсеть — нужно помнить порядок и зависимости
yc vpc subnet create --name app-a --network-name my-vpc ...
# Если упало на шаге 5 из 20 — непонятно, что успело создаться
```

**Декларативный подход** (Terraform):
```hcl
# Описываем ЖЕЛАЕМОЕ состояние — Terraform сам решает порядок создания
resource "yandex_vpc_subnet" "app_a" {
  network_id = yandex_vpc_network.main.id  # Зависимость явная и автоматическая
  ...
}
```

| Критерий | Bash-скрипты | Terraform |
|---|---|---|
| Идемпотентность | Нет (повторный запуск = дублирование) | Да (`terraform apply` всегда даёт целевое состояние) |
| Управление зависимостями | Вручную (порядок команд) | Автоматически (граф зависимостей) |
| Откат изменений | Ручной, сложный | `terraform destroy` или revert кода + `apply` |
| Видимость изменений | Нет | `terraform plan` показывает diff перед применением |
| Drift detection | Невозможен | `terraform plan` выявляет расхождение с реальностью |
| Командная работа | Трудно, нет state | State в Object Storage, locking через YDB |

### 3.2 Конкретные выгоды для «Будущее 2.0»

**Безопасность**: `terraform plan` перед каждым `apply` — команда видит, что изменится, до применения. Случайное удаление продакшн-базы будет видно в плане.

**Аудит**: Git history Terraform-кода = полная история изменений инфраструктуры с автором, датой и причиной (commit message). Критично для финтех-compliance.

**Ревью**: Изменения инфраструктуры проходят Pull Request — такой же процесс, как изменения кода приложений.

---

## 4. IaC и воспроизводимость

### 4.1 Одинаковые окружения

```bash
# Dev окружение
TF_VAR_environment=dev terraform apply

# Staging — идентичная структура, другие размеры
TF_VAR_environment=staging terraform apply -var="k8s_node_max=10"

# Production — та же конфигурация, prod-параметры
TF_VAR_environment=prod terraform apply -var-file=prod.tfvars
```

Все три окружения создаются из одного кода. Гарантируется структурная идентичность: если баг воспроизводится в prod, его можно воспроизвести в dev.

### 4.2 Disaster Recovery

При полной потере инфраструктуры (аварийная ситуация):
```bash
git clone <infrastructure-repo>
cd Task4
# Установить секреты через env vars
terraform init
terraform apply  # За ~30 минут инфраструктура восстановлена
```

**Без IaC**: восстановление занимает дни и требует «героических» усилий команды.

### 4.3 Масштабируемость

**Горизонтальное масштабирование (добавление нового домена)**:
```hcl
# Добавить новый домен "pharma" — 5 строк изменений в main.tf:
resource "yandex_mdb_postgresql_cluster" "pharma" {
  name = "${local.project}-${local.env}-pharma-pg"
  # ... аналогично clinic/fintech
}
```
`terraform plan` покажет только новые ресурсы — существующие домены не затронуты.

**Вертикальное масштабирование (увеличение ресурсов)**:
```hcl
# В terraform.tfvars изменить preset для финтеха при росте нагрузки:
fintech_db_preset = "s3-c8-m32"  # Было s3-c4-m16
```
`terraform apply` выполнит rolling update PostgreSQL без downtime (managed service).

**Kubernetes autoscaling**: Node Groups настроены с `auto_scale` — Kubernetes сам добавляет ноды при нехватке ресурсов, убирает при простое. Terraform управляет границами (min/max), а K8s — оперативным scaling.

---

## 5. Что управляется Terraform vs. вручную

### Управляется Terraform (полная автоматизация)

| Ресурс | Причина автоматизации |
|---|---|
| VPC, подсети, NAT, Route Table | Базовая сеть — фундамент всей инфраструктуры |
| Security Groups (4 штуки) | Изменения правил firewall должны быть в Git с ревью |
| Bastion VM + Disk | Повторяемое создание с идентичной конфигурацией |
| Managed Kafka + Topics + Users | Kafka-топики — контракты между доменами; версионирование обязательно |
| Managed PostgreSQL (2 кластера) + Users + DBs | Схема данных под контролем версий; credentials в state |
| Object Storage Bucket + структура директорий | Lakehouse создаётся с нужными политиками с первого раза |
| IAM Service Accounts + Bindings + Static Keys | Принцип least privilege; изменения прав должны быть аудируемы |
| Kubernetes Cluster + Node Groups | Конфигурация кластера определяет безопасность и производительность |

### Вручную (первичная настройка / не автоматизировано в MVP)

| Действие | Причина ручной настройки |
|---|---|
| Генерация SSH key pair | Приватный ключ не должен попадать в Terraform state |
| Создание bucket для Terraform state | Bootstrap-проблема: state нужен до создания bucket |
| DNS-записи (внешние) | Управляются в регистраторе домена (вне Yandex Cloud) |
| TLS/SSL сертификаты | cert-manager в K8s создаёт их автоматически при деплое приложений |
| Helm chart деплой (Kong, Grafana) | Application layer — управляется GitOps (ArgoCD), не Terraform |
| Инициализация дефолтных данных БД | Миграции БД — ответственность application-команд (Flyway, Liquibase) |
| Мониторинг дашборды | Grafana — отдельный IaC или Helm chart |
| Первичное создание Yandex Cloud Cloud/Folder | Организационный уровень — создаётся через UI один раз |

---

## 6. Команды для проверки

```bash
# 1. Инициализация (скачать провайдер)
terraform init

# 2. Проверка конфигурации без применения
terraform validate
terraform fmt -check

# 3. Plan — показать изменения
terraform plan -var-file=terraform.tfvars -out=tfplan

# 4. Apply — применить инфраструктуру
terraform apply tfplan

# 5. Показать outputs
terraform output deployment_summary

# 6. Проверить конкретный output
terraform output -raw bastion_public_ip
terraform output -json kafka_broker_fqdns

# 7. Destroy — удалить всю инфраструктуру
terraform destroy -var-file=terraform.tfvars
```

### Ожидаемые ресурсы после `terraform apply`

```
Plan: 42 to add, 0 to change, 0 to destroy.

Resources created:
  yandex_vpc_network              × 1   (VPC)
  yandex_vpc_subnet               × 5   (mgmt-a, app-a, app-b, data-a, data-b)
  yandex_vpc_gateway              × 1   (NAT Gateway)
  yandex_vpc_route_table          × 1
  yandex_vpc_security_group       × 4   (bastion, kafka, postgresql, k8s)
  yandex_iam_service_account      × 2   (k8s-sa, storage-sa)
  yandex_resourcemanager_...      × 2   (IAM bindings)
  yandex_iam_service_account_...  × 1   (static key)
  yandex_storage_bucket           × 1   (lakehouse)
  yandex_storage_object           × 4   (domain prefixes)
  yandex_mdb_kafka_cluster        × 1
  yandex_mdb_kafka_topic          × 5
  yandex_mdb_kafka_user           × 3
  yandex_mdb_postgresql_cluster   × 2   (clinic, fintech)
  yandex_mdb_postgresql_user      × 2
  yandex_mdb_postgresql_database  × 2
  yandex_compute_disk             × 1   (bastion boot)
  yandex_compute_instance         × 1   (bastion)
  yandex_kubernetes_cluster       × 1
  yandex_kubernetes_node_group    × 2   (general, ai)
```

---

## 7. Стоимость инфраструктуры (оценка, dev-окружение)

| Ресурс | Конфигурация | ~Стоимость/мес |
|---|---|---|
| Bastion VM | s3-c2-m2, preem, SSD 20 GB | ~300 ₽ |
| Kafka cluster | 2 брокера s3-c2-m8, SSD 100 GB × 2 | ~8 000 ₽ |
| PostgreSQL clinic | s3-c2-m8, SSD 50 GB × 2 hosts | ~5 000 ₽ |
| PostgreSQL fintech | s3-c4-m16, SSD 100 GB × 2 hosts | ~12 000 ₽ |
| K8s cluster | Regional master + 2 general nodes preem | ~6 000 ₽ |
| Object Storage | 100 GB + трафик | ~300 ₽ |
| NAT Gateway | Исходящий трафик | ~500 ₽ |
| **ИТОГО dev** | | **~32 000 ₽/мес** |

В **prod** (без preemptible, prod-размеры):
- Kafka: 4 брокера s3-c4-m16 → ~30 000 ₽
- PG fintech: s3-c8-m32 → ~25 000 ₽
- K8s: 5 general + 2 AI nodes → ~25 000 ₽
- **Итого prod: ~100 000 ₽/мес** (~$1100)

Для сравнения: on-premise аналог потребовал бы ~5–10 серверов ценой 500 000–1 500 000 ₽ единовременно плюс поддержку.
