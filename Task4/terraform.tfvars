###############################################################################
# terraform.tfvars — «Будущее 2.0» Variable Values
#
# ВАЖНО: этот файл содержит только НЕСЕКРЕТНЫЕ значения.
# Секреты передавать через переменные окружения:
#
#   export TF_VAR_yc_token="your-iam-token-or-api-key"
#   export TF_VAR_yc_cloud_id="b1gxxxxxxxxxxxxxxxxx"
#   export TF_VAR_yc_folder_id="b1gxxxxxxxxxxxxxxxxx"
#   export TF_VAR_clinic_db_password="StrongPass1!"
#   export TF_VAR_fintech_db_password="StrongPass2!"
#   export TF_VAR_kafka_clinic_password="StrongPass3!"
#   export TF_VAR_kafka_fintech_password="StrongPass4!"
#   export TF_VAR_kafka_consumer_password="StrongPass5!"
#   export TF_VAR_bastion_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
#
# Или создать файл secrets.auto.tfvars (добавлен в .gitignore):
#   yc_token               = "..."
#   yc_cloud_id            = "..."
#   ...
###############################################################################

# ─── Project ──────────────────────────────────────────────────────────────────
project_name = "future20"
environment  = "dev"

# ─── Yandex Cloud (несекретные) ───────────────────────────────────────────────
default_zone = "ru-central1-a"

# ─── Network ──────────────────────────────────────────────────────────────────
subnet_cidrs = {
  mgmt_a = "10.10.0.0/24"   # Bastion, admin
  app_a  = "10.10.1.0/24"   # K8s nodes (zone A)
  app_b  = "10.10.2.0/24"   # K8s nodes (zone B)
  data_a = "10.10.3.0/24"   # Kafka + PG (zone A)
  data_b = "10.10.4.0/24"   # Kafka + PG (zone B, HA)
}

# В prod заменить на конкретный IP офиса или VPN-шлюза
# Пример: allowed_ssh_cidrs = ["203.0.113.0/24"]
allowed_ssh_cidrs = ["0.0.0.0/0"]

# ─── Object Storage / Lakehouse ───────────────────────────────────────────────
# Объекты старше 90 дней переходят в COLD-хранилище (дешевле)
lakehouse_transition_days = 90

# ─── Kafka ────────────────────────────────────────────────────────────────────
kafka_version          = "3.5"
kafka_brokers_count    = 1          # 1 брокер на зону = 2 брокера суммарно (A+B)
kafka_broker_preset    = "s3-c2-m8" # 2 vCPU, 8 GB RAM — достаточно для dev/staging
kafka_broker_disk_size = 100        # 100 GB SSD на брокер

# ─── PostgreSQL ───────────────────────────────────────────────────────────────
postgresql_version   = "15"

# Домен Клиники — умеренная нагрузка (OLTP, визиты)
clinic_db_preset    = "s3-c2-m8"  # 2 vCPU, 8 GB RAM
clinic_db_disk_size = 50          # 50 GB SSD

# Домен Финтех — высокая нагрузка (платежи, кредиты, транзакции)
fintech_db_preset    = "s3-c4-m16" # 4 vCPU, 16 GB RAM
fintech_db_disk_size = 100         # 100 GB SSD

# ─── Bastion ──────────────────────────────────────────────────────────────────
# Ubuntu 22.04 LTS — стабильная LTS-версия, поддержка до 2027
bastion_image_id  = "fd8smb7fj0n1tqhs7do3"
bastion_disk_size = 20  # 20 GB — только ОС и admin-утилиты
bastion_cores     = 2
bastion_memory    = 2   # 2 GB достаточно для jump-хоста

# bastion_ssh_public_key — передаётся через TF_VAR_bastion_ssh_public_key

# ─── Kubernetes ───────────────────────────────────────────────────────────────
k8s_version = "1.28"

# General Node Group — Clinic App, Fintech API, Portal, dbt
k8s_node_cores    = 4
k8s_node_memory   = 8    # 8 GB на ноду
k8s_node_disk_size = 64  # 64 GB SSD boot disk
k8s_node_min      = 1    # В dev — минимум 1 нода чтобы держать базовые сервисы
k8s_node_max      = 5    # Максимум 5 нод (горизонтальный autoscale)
k8s_node_initial  = 2    # Стартовый размер

# AI Node Group — Python inference, MLflow (scale-to-zero в idle)
k8s_ai_node_cores  = 8
k8s_ai_node_memory = 32  # 32 GB — для ML-моделей в памяти
k8s_ai_node_max    = 3   # Максимум 3 AI-ноды одновременно
