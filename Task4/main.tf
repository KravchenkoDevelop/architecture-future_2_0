###############################################################################
# «Будущее 2.0» — Cloud Infrastructure
# Provider : Yandex Cloud (yandex-cloud/yandex)
# Region   : ru-central1  (zones: a, b)
# Approach : IaaS + Managed Services, declarative Terraform
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.95"
    }
  }

  # Рекомендуется: remote state в Object Storage
  # backend "s3" {
  #   endpoint   = "storage.yandexcloud.net"
  #   bucket     = "<your-tf-state-bucket>"
  #   region     = "ru-central1"
  #   key        = "future20/terraform.tfstate"
  #   access_key = var.backend_access_key
  #   secret_key = var.backend_secret_key
  #   skip_region_validation      = true
  #   skip_credentials_validation = true
  # }
}

provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = var.default_zone
}

###############################################################################
# Locals
###############################################################################

locals {
  project = var.project_name
  env     = var.environment

  common_labels = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
  }
}

###############################################################################
# 1. VPC NETWORK
###############################################################################

resource "yandex_vpc_network" "main" {
  name        = "${local.project}-${local.env}-vpc"
  description = "Main VPC for Future 2.0 platform"
  labels      = local.common_labels
}

# ─── Subnet: Management (Bastion, Terraform runner) ─────────────────────────
resource "yandex_vpc_subnet" "mgmt_a" {
  name           = "${local.project}-${local.env}-mgmt-a"
  description    = "Management subnet — zone A"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.subnet_cidrs["mgmt_a"]]
  route_table_id = yandex_vpc_route_table.nat.id
  labels         = merge(local.common_labels, { tier = "management" })
}

# ─── Subnet: Applications (K8s nodes) — zone A ──────────────────────────────
resource "yandex_vpc_subnet" "app_a" {
  name           = "${local.project}-${local.env}-app-a"
  description    = "Application subnet — zone A"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.subnet_cidrs["app_a"]]
  route_table_id = yandex_vpc_route_table.nat.id
  labels         = merge(local.common_labels, { tier = "application" })
}

# ─── Subnet: Applications (K8s nodes) — zone B ──────────────────────────────
resource "yandex_vpc_subnet" "app_b" {
  name           = "${local.project}-${local.env}-app-b"
  description    = "Application subnet — zone B"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.subnet_cidrs["app_b"]]
  route_table_id = yandex_vpc_route_table.nat.id
  labels         = merge(local.common_labels, { tier = "application" })
}

# ─── Subnet: Data (Kafka, PostgreSQL) — zone A ──────────────────────────────
resource "yandex_vpc_subnet" "data_a" {
  name           = "${local.project}-${local.env}-data-a"
  description    = "Data subnet — zone A"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.subnet_cidrs["data_a"]]
  route_table_id = yandex_vpc_route_table.nat.id
  labels         = merge(local.common_labels, { tier = "data" })
}

# ─── Subnet: Data (Kafka, PostgreSQL) — zone B ──────────────────────────────
resource "yandex_vpc_subnet" "data_b" {
  name           = "${local.project}-${local.env}-data-b"
  description    = "Data subnet — zone B"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.subnet_cidrs["data_b"]]
  route_table_id = yandex_vpc_route_table.nat.id
  labels         = merge(local.common_labels, { tier = "data" })
}

###############################################################################
# 2. NAT GATEWAY + ROUTE TABLE
###############################################################################

resource "yandex_vpc_gateway" "nat" {
  name        = "${local.project}-${local.env}-nat-gw"
  description = "Shared NAT gateway for all private subnets"

  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "nat" {
  name       = "${local.project}-${local.env}-rt-nat"
  network_id = yandex_vpc_network.main.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat.id
  }
}

###############################################################################
# 3. SECURITY GROUPS
###############################################################################

# ─── SG: Bastion ─────────────────────────────────────────────────────────────
resource "yandex_vpc_security_group" "bastion" {
  name        = "${local.project}-${local.env}-sg-bastion"
  description = "SSH access to bastion from allowed CIDRs only"
  network_id  = yandex_vpc_network.main.id
  labels      = merge(local.common_labels, { role = "bastion" })

  ingress {
    protocol       = "TCP"
    description    = "SSH from allowed IPs"
    v4_cidr_blocks = var.allowed_ssh_cidrs
    port           = 22
  }

  egress {
    protocol       = "ANY"
    description    = "All outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# ─── SG: Kafka ───────────────────────────────────────────────────────────────
resource "yandex_vpc_security_group" "kafka" {
  name        = "${local.project}-${local.env}-sg-kafka"
  description = "Kafka broker access from app subnets"
  network_id  = yandex_vpc_network.main.id
  labels      = merge(local.common_labels, { role = "kafka" })

  ingress {
    protocol       = "TCP"
    description    = "Kafka plaintext from app subnets"
    v4_cidr_blocks = [var.subnet_cidrs["app_a"], var.subnet_cidrs["app_b"]]
    port           = 9092
  }

  ingress {
    protocol       = "TCP"
    description    = "Kafka SSL from app subnets"
    v4_cidr_blocks = [var.subnet_cidrs["app_a"], var.subnet_cidrs["app_b"]]
    port           = 9093
  }

  ingress {
    protocol       = "TCP"
    description    = "Kafka admin from bastion"
    v4_cidr_blocks = [var.subnet_cidrs["mgmt_a"]]
    port           = 9092
  }

  egress {
    protocol       = "ANY"
    description    = "All outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# ─── SG: PostgreSQL ──────────────────────────────────────────────────────────
resource "yandex_vpc_security_group" "postgresql" {
  name        = "${local.project}-${local.env}-sg-postgresql"
  description = "PostgreSQL access from app and management subnets"
  network_id  = yandex_vpc_network.main.id
  labels      = merge(local.common_labels, { role = "database" })

  ingress {
    protocol       = "TCP"
    description    = "PostgreSQL from app subnet A"
    v4_cidr_blocks = [var.subnet_cidrs["app_a"]]
    port           = 5432
  }

  ingress {
    protocol       = "TCP"
    description    = "PostgreSQL from app subnet B"
    v4_cidr_blocks = [var.subnet_cidrs["app_b"]]
    port           = 5432
  }

  ingress {
    protocol       = "TCP"
    description    = "PostgreSQL admin from bastion"
    v4_cidr_blocks = [var.subnet_cidrs["mgmt_a"]]
    port           = 5432
  }

  egress {
    protocol       = "ANY"
    description    = "All outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# ─── SG: Kubernetes ──────────────────────────────────────────────────────────
resource "yandex_vpc_security_group" "k8s" {
  name        = "${local.project}-${local.env}-sg-k8s"
  description = "Kubernetes cluster traffic rules"
  network_id  = yandex_vpc_network.main.id
  labels      = merge(local.common_labels, { role = "kubernetes" })

  ingress {
    protocol       = "TCP"
    description    = "K8s API HTTPS"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  ingress {
    protocol       = "ANY"
    description    = "Internal cluster communication"
    v4_cidr_blocks = [var.subnet_cidrs["app_a"], var.subnet_cidrs["app_b"]]
  }

  ingress {
    protocol       = "TCP"
    description    = "NodePort range"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 30000
    to_port        = 32767
  }

  egress {
    protocol       = "ANY"
    description    = "All outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

###############################################################################
# 4. IAM SERVICE ACCOUNTS
###############################################################################

# ─── SA: Kubernetes ──────────────────────────────────────────────────────────
resource "yandex_iam_service_account" "k8s" {
  name        = "${local.project}-${local.env}-k8s-sa"
  description = "Service account for Kubernetes cluster and node groups"
}

resource "yandex_resourcemanager_folder_iam_binding" "k8s_editor" {
  folder_id = var.yc_folder_id
  role      = "editor"
  members   = ["serviceAccount:${yandex_iam_service_account.k8s.id}"]
}

# ─── SA: Object Storage (Lakehouse) ──────────────────────────────────────────
resource "yandex_iam_service_account" "storage" {
  name        = "${local.project}-${local.env}-storage-sa"
  description = "Service account for Lakehouse Object Storage access"
}

resource "yandex_resourcemanager_folder_iam_binding" "storage_admin" {
  folder_id = var.yc_folder_id
  role      = "storage.admin"
  members   = ["serviceAccount:${yandex_iam_service_account.storage.id}"]
}

resource "yandex_iam_service_account_static_access_key" "storage_key" {
  service_account_id = yandex_iam_service_account.storage.id
  description        = "Static key for Lakehouse S3 API access"
}

###############################################################################
# 5. OBJECT STORAGE — DATA LAKEHOUSE
###############################################################################

resource "yandex_storage_bucket" "lakehouse" {
  bucket     = "${local.project}-${local.env}-lakehouse"
  access_key = yandex_iam_service_account_static_access_key.storage_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.storage_key.secret_key

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    id      = "lakehouse-cold-transition"
    enabled = true

    transition {
      days          = var.lakehouse_transition_days
      storage_class = "COLD"
    }
  }

  tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
    purpose     = "data-lakehouse"
  }
}

# Маркерные объекты для структуры доменов в Lakehouse
resource "yandex_storage_object" "lakehouse_clinic" {
  bucket     = yandex_storage_bucket.lakehouse.bucket
  access_key = yandex_iam_service_account_static_access_key.storage_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.storage_key.secret_key
  key        = "domains/clinic/.keep"
  content    = ""
}

resource "yandex_storage_object" "lakehouse_fintech" {
  bucket     = yandex_storage_bucket.lakehouse.bucket
  access_key = yandex_iam_service_account_static_access_key.storage_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.storage_key.secret_key
  key        = "domains/fintech/.keep"
  content    = ""
}

resource "yandex_storage_object" "lakehouse_ai" {
  bucket     = yandex_storage_bucket.lakehouse.bucket
  access_key = yandex_iam_service_account_static_access_key.storage_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.storage_key.secret_key
  key        = "domains/ai/.keep"
  content    = ""
}

resource "yandex_storage_object" "lakehouse_hq" {
  bucket     = yandex_storage_bucket.lakehouse.bucket
  access_key = yandex_iam_service_account_static_access_key.storage_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.storage_key.secret_key
  key        = "domains/hq/.keep"
  content    = ""
}

###############################################################################
# 6. MANAGED KAFKA
###############################################################################

resource "yandex_mdb_kafka_cluster" "main" {
  name        = "${local.project}-${local.env}-kafka"
  environment = upper(var.environment) == "DEV" ? "PRODUCTION" : upper(var.environment)
  network_id  = yandex_vpc_network.main.id
  subnet_ids  = [yandex_vpc_subnet.data_a.id, yandex_vpc_subnet.data_b.id]

  security_group_ids = [yandex_vpc_security_group.kafka.id]

  config {
    version          = var.kafka_version
    brokers_count    = var.kafka_brokers_count
    zones            = ["ru-central1-a", "ru-central1-b"]
    assign_public_ip = false

    kafka {
      resources {
        resource_preset_id = var.kafka_broker_preset
        disk_type_id       = "network-ssd"
        disk_size          = var.kafka_broker_disk_size
      }

      kafka_config {
        auto_create_topics_enable  = false
        default_replication_factor = 2
        min_insync_replicas        = 1
        num_partitions             = 6
        compression_type           = "LZ4"
        log_retention_bytes        = 5368709120  # 5 GiB
        log_retention_ms           = 604800000   # 7 days
      }
    }

    zookeeper {
      resources {
        resource_preset_id = "s3-c2-m8"
        disk_type_id       = "network-ssd"
        disk_size          = 20
      }
    }
  }

  labels = local.common_labels
}

# ─── Kafka Topics ─────────────────────────────────────────────────────────────
resource "yandex_mdb_kafka_topic" "clinic_visits" {
  cluster_id         = yandex_mdb_kafka_cluster.main.id
  name               = "clinic.visit.events"
  partitions         = 6
  replication_factor = 2

  topic_config {
    compression_type = "LZ4"
    retention_ms     = 604800000
  }
}

resource "yandex_mdb_kafka_topic" "fintech_payments" {
  cluster_id         = yandex_mdb_kafka_cluster.main.id
  name               = "fintech.payment.events"
  partitions         = 6
  replication_factor = 2

  topic_config {
    compression_type = "LZ4"
    retention_ms     = 604800000
  }
}

resource "yandex_mdb_kafka_topic" "fintech_loans" {
  cluster_id         = yandex_mdb_kafka_cluster.main.id
  name               = "fintech.loan.events"
  partitions         = 3
  replication_factor = 2

  topic_config {
    compression_type = "LZ4"
    retention_ms     = 604800000
  }
}

resource "yandex_mdb_kafka_topic" "ai_inference" {
  cluster_id         = yandex_mdb_kafka_cluster.main.id
  name               = "ai.inference.results"
  partitions         = 3
  replication_factor = 2

  topic_config {
    compression_type = "LZ4"
    retention_ms     = 259200000  # 3 days
  }
}

resource "yandex_mdb_kafka_topic" "pharma_catalog" {
  cluster_id         = yandex_mdb_kafka_cluster.main.id
  name               = "partner.pharma.catalog"
  partitions         = 1
  replication_factor = 2

  topic_config {
    compression_type = "NONE"
    retention_ms     = -1  # Бессрочно
  }
}

# ─── Kafka Users ─────────────────────────────────────────────────────────────
resource "yandex_mdb_kafka_user" "clinic_producer" {
  cluster_id = yandex_mdb_kafka_cluster.main.id
  name       = "clinic-producer"
  password   = var.kafka_clinic_password

  permission {
    topic_name = yandex_mdb_kafka_topic.clinic_visits.name
    role       = "ACCESS_ROLE_PRODUCER"
  }
}

resource "yandex_mdb_kafka_user" "fintech_producer" {
  cluster_id = yandex_mdb_kafka_cluster.main.id
  name       = "fintech-producer"
  password   = var.kafka_fintech_password

  permission {
    topic_name = yandex_mdb_kafka_topic.fintech_payments.name
    role       = "ACCESS_ROLE_PRODUCER"
  }

  permission {
    topic_name = yandex_mdb_kafka_topic.fintech_loans.name
    role       = "ACCESS_ROLE_PRODUCER"
  }
}

resource "yandex_mdb_kafka_user" "data_consumer" {
  cluster_id = yandex_mdb_kafka_cluster.main.id
  name       = "data-consumer"
  password   = var.kafka_consumer_password

  permission {
    topic_name = yandex_mdb_kafka_topic.clinic_visits.name
    role       = "ACCESS_ROLE_CONSUMER"
  }

  permission {
    topic_name = yandex_mdb_kafka_topic.fintech_payments.name
    role       = "ACCESS_ROLE_CONSUMER"
  }

  permission {
    topic_name = yandex_mdb_kafka_topic.fintech_loans.name
    role       = "ACCESS_ROLE_CONSUMER"
  }

  permission {
    topic_name = yandex_mdb_kafka_topic.ai_inference.name
    role       = "ACCESS_ROLE_CONSUMER"
  }
}

###############################################################################
# 7. MANAGED POSTGRESQL — DOMAIN: CLINIC
###############################################################################

resource "yandex_mdb_postgresql_cluster" "clinic" {
  name        = "${local.project}-${local.env}-clinic-pg"
  environment = upper(var.environment) == "DEV" ? "PRODUCTION" : upper(var.environment)
  network_id  = yandex_vpc_network.main.id

  security_group_ids = [yandex_vpc_security_group.postgresql.id]

  config {
    version = var.postgresql_version

    resources {
      resource_preset_id = var.clinic_db_preset
      disk_type_id       = "network-ssd"
      disk_size          = var.clinic_db_disk_size
    }

    backup_window_start {
      hours   = 2
      minutes = 0
    }

    backup_retain_period_days = 7

    access {
      data_lens     = false
      web_sql       = false
      serverless    = false
      data_transfer = false
    }
  }

  host {
    zone             = "ru-central1-a"
    subnet_id        = yandex_vpc_subnet.data_a.id
    assign_public_ip = false
    name             = "clinic-pg-host-a"
  }

  host {
    zone             = "ru-central1-b"
    subnet_id        = yandex_vpc_subnet.data_b.id
    assign_public_ip = false
    name             = "clinic-pg-host-b"
  }

  labels = merge(local.common_labels, { domain = "clinic" })
}

resource "yandex_mdb_postgresql_user" "clinic_app" {
  cluster_id = yandex_mdb_postgresql_cluster.clinic.id
  name       = "clinic_app"
  password   = var.clinic_db_password
}

resource "yandex_mdb_postgresql_database" "clinic_db" {
  cluster_id = yandex_mdb_postgresql_cluster.clinic.id
  name       = "clinic_operational"
  owner      = yandex_mdb_postgresql_user.clinic_app.name

  depends_on = [yandex_mdb_postgresql_user.clinic_app]
}

###############################################################################
# 8. MANAGED POSTGRESQL — DOMAIN: FINTECH
###############################################################################

resource "yandex_mdb_postgresql_cluster" "fintech" {
  name        = "${local.project}-${local.env}-fintech-pg"
  environment = upper(var.environment) == "DEV" ? "PRODUCTION" : upper(var.environment)
  network_id  = yandex_vpc_network.main.id

  security_group_ids = [yandex_vpc_security_group.postgresql.id]

  config {
    version = var.postgresql_version

    resources {
      resource_preset_id = var.fintech_db_preset
      disk_type_id       = "network-ssd"
      disk_size          = var.fintech_db_disk_size
    }

    backup_window_start {
      hours   = 3
      minutes = 0
    }

    backup_retain_period_days = 14  # Финтех: расширенный период для compliance

    access {
      data_lens     = false
      web_sql       = false
      serverless    = false
      data_transfer = false
    }
  }

  host {
    zone             = "ru-central1-a"
    subnet_id        = yandex_vpc_subnet.data_a.id
    assign_public_ip = false
    name             = "fintech-pg-host-a"
  }

  host {
    zone             = "ru-central1-b"
    subnet_id        = yandex_vpc_subnet.data_b.id
    assign_public_ip = false
    name             = "fintech-pg-host-b"
  }

  labels = merge(local.common_labels, { domain = "fintech" })
}

resource "yandex_mdb_postgresql_user" "fintech_app" {
  cluster_id = yandex_mdb_postgresql_cluster.fintech.id
  name       = "fintech_app"
  password   = var.fintech_db_password
}

resource "yandex_mdb_postgresql_database" "fintech_db" {
  cluster_id = yandex_mdb_postgresql_cluster.fintech.id
  name       = "fintech_core"
  owner      = yandex_mdb_postgresql_user.fintech_app.name

  depends_on = [yandex_mdb_postgresql_user.fintech_app]
}

###############################################################################
# 9. BASTION HOST (IaaS VM)
###############################################################################

resource "yandex_compute_disk" "bastion_boot" {
  name     = "${local.project}-${local.env}-bastion-boot"
  type     = "network-ssd"
  zone     = "ru-central1-a"
  image_id = var.bastion_image_id
  size     = var.bastion_disk_size

  labels = merge(local.common_labels, { role = "bastion" })
}

resource "yandex_compute_instance" "bastion" {
  name        = "${local.project}-${local.env}-bastion"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores         = var.bastion_cores
    memory        = var.bastion_memory
    core_fraction = 20  # Экономия: 20% гарантированной доли CPU
  }

  boot_disk {
    disk_id = yandex_compute_disk.bastion_boot.id
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.mgmt_a.id
    nat                = true  # Публичный IP — необходим для внешнего SSH доступа
    security_group_ids = [yandex_vpc_security_group.bastion.id]
  }

  metadata = {
    ssh-keys           = "ubuntu:${var.bastion_ssh_public_key}"
    serial-port-enable = "0"
    user-data          = <<-EOT
      #cloud-config
      users:
        - name: ubuntu
          groups: sudo
          shell: /bin/bash
          sudo: ['ALL=(ALL) NOPASSWD:ALL']
          ssh-authorized-keys:
            - ${var.bastion_ssh_public_key}
      package_update: true
      packages:
        - postgresql-client
        - kafkacat
        - curl
        - wget
        - jq
        - net-tools
    EOT
  }

  scheduling_policy {
    # В dev используем прерываемые ВМ для экономии (до 80% скидки)
    preemptible = var.environment == "dev"
  }

  labels = merge(local.common_labels, { role = "bastion" })

  depends_on = [yandex_vpc_subnet.mgmt_a]
}

###############################################################################
# 10. KUBERNETES CLUSTER (Regional HA)
###############################################################################

resource "yandex_kubernetes_cluster" "main" {
  name        = "${local.project}-${local.env}-k8s"
  description = "Main application cluster for Future 2.0"
  network_id  = yandex_vpc_network.main.id

  master {
    version   = var.k8s_version
    public_ip = false  # Приватный endpoint — доступ через VPN/Bastion

    regional {
      region = "ru-central1"

      location {
        zone      = "ru-central1-a"
        subnet_id = yandex_vpc_subnet.app_a.id
      }

      location {
        zone      = "ru-central1-b"
        subnet_id = yandex_vpc_subnet.app_b.id
      }
    }

    security_group_ids = [yandex_vpc_security_group.k8s.id]

    maintenance_policy {
      auto_upgrade = true
      maintenance_window {
        day        = "sunday"
        start_time = "03:00"
        duration   = "3h"
      }
    }
  }

  service_account_id      = yandex_iam_service_account.k8s.id
  node_service_account_id = yandex_iam_service_account.k8s.id

  release_channel = "STABLE"
  labels          = local.common_labels

  depends_on = [
    yandex_resourcemanager_folder_iam_binding.k8s_editor,
    yandex_vpc_subnet.app_a,
    yandex_vpc_subnet.app_b,
  ]
}

# ─── Node Group: General Purpose ─────────────────────────────────────────────
resource "yandex_kubernetes_node_group" "general" {
  cluster_id  = yandex_kubernetes_cluster.main.id
  name        = "${local.project}-${local.env}-ng-general"
  description = "General purpose nodes — Clinic App, Fintech, Portal"
  version     = var.k8s_version

  instance_template {
    platform_id = "standard-v3"

    resources {
      cores  = var.k8s_node_cores
      memory = var.k8s_node_memory
    }

    boot_disk {
      type = "network-ssd"
      size = var.k8s_node_disk_size
    }

    scheduling_policy {
      preemptible = var.environment == "dev"
    }

    network_interface {
      subnet_ids         = [yandex_vpc_subnet.app_a.id]
      security_group_ids = [yandex_vpc_security_group.k8s.id]
      nat                = false
    }

    metadata = {
      ssh-keys = "ubuntu:${var.bastion_ssh_public_key}"
    }
  }

  scale_policy {
    auto_scale {
      min     = var.k8s_node_min
      max     = var.k8s_node_max
      initial = var.k8s_node_initial
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-a"
    }
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true
    maintenance_window {
      day        = "sunday"
      start_time = "04:00"
      duration   = "3h"
    }
  }

  labels = merge(local.common_labels, { role = "general" })
}

# ─── Node Group: AI/ML Workloads ─────────────────────────────────────────────
resource "yandex_kubernetes_node_group" "ai" {
  cluster_id  = yandex_kubernetes_cluster.main.id
  name        = "${local.project}-${local.env}-ng-ai"
  description = "AI/ML workload nodes — Python inference, MLflow"
  version     = var.k8s_version

  instance_template {
    platform_id = "standard-v3"

    resources {
      cores  = var.k8s_ai_node_cores
      memory = var.k8s_ai_node_memory
    }

    boot_disk {
      type = "network-ssd"
      size = var.k8s_node_disk_size
    }

    scheduling_policy {
      preemptible = var.environment == "dev"
    }

    network_interface {
      subnet_ids         = [yandex_vpc_subnet.app_a.id]
      security_group_ids = [yandex_vpc_security_group.k8s.id]
      nat                = false
    }

    metadata = {
      ssh-keys = "ubuntu:${var.bastion_ssh_public_key}"
    }
  }

  scale_policy {
    auto_scale {
      min     = 0                       # Scale to zero when no AI workloads
      max     = var.k8s_ai_node_max
      initial = 0
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-a"
    }
  }

  node_labels = {
    "workload-type" = "ai"
  }

  node_taints = ["workload-type=ai:NoSchedule"]

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true
    maintenance_window {
      day        = "sunday"
      start_time = "05:00"
      duration   = "3h"
    }
  }

  labels = merge(local.common_labels, { role = "ai" })
}
