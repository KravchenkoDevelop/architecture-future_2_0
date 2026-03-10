###############################################################################
# variables.tf — «Будущее 2.0» Infrastructure Variables
###############################################################################

# ─── Yandex Cloud Credentials ────────────────────────────────────────────────

variable "yc_token" {
  description = "Yandex Cloud IAM token or service account key JSON. Set via TF_VAR_yc_token."
  type        = string
  sensitive   = true
}

variable "yc_cloud_id" {
  description = "Yandex Cloud Cloud ID. Found in the Cloud console."
  type        = string
}

variable "yc_folder_id" {
  description = "Yandex Cloud Folder ID where all resources will be created."
  type        = string
}

variable "default_zone" {
  description = "Default availability zone for single-zone resources."
  type        = string
  default     = "ru-central1-a"
}

# ─── Project & Environment ────────────────────────────────────────────────────

variable "project_name" {
  description = "Project name prefix applied to all resource names."
  type        = string
  default     = "future20"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 2-20 lowercase letters, numbers, or hyphens."
  }
}

variable "environment" {
  description = "Deployment environment. Affects resource sizing and preemptible mode."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "subnet_cidrs" {
  description = "CIDR blocks for each subnet tier. All must be within 10.10.0.0/16."
  type        = map(string)
  default = {
    mgmt_a = "10.10.0.0/24"  # Management: bastion, admin tools
    app_a  = "10.10.1.0/24"  # Application zone A: K8s nodes
    app_b  = "10.10.2.0/24"  # Application zone B: K8s nodes
    data_a = "10.10.3.0/24"  # Data zone A: Kafka, PostgreSQL
    data_b = "10.10.4.0/24"  # Data zone B: Kafka, PostgreSQL (HA)
  }
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to the bastion host. Restrict to office/VPN in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ─── Object Storage / Lakehouse ───────────────────────────────────────────────

variable "lakehouse_transition_days" {
  description = "Number of days before Lakehouse objects transition to COLD storage class."
  type        = number
  default     = 90

  validation {
    condition     = var.lakehouse_transition_days >= 30
    error_message = "lakehouse_transition_days must be at least 30."
  }
}

# ─── Kafka ────────────────────────────────────────────────────────────────────

variable "kafka_version" {
  description = "Kafka version. See Yandex Cloud documentation for supported versions."
  type        = string
  default     = "3.5"
}

variable "kafka_brokers_count" {
  description = "Number of Kafka brokers per zone. Total brokers = brokers_count × number of zones (2)."
  type        = number
  default     = 1

  validation {
    condition     = var.kafka_brokers_count >= 1 && var.kafka_brokers_count <= 10
    error_message = "kafka_brokers_count must be between 1 and 10."
  }
}

variable "kafka_broker_preset" {
  description = "Yandex Cloud resource preset for Kafka brokers (e.g. s3-c2-m8 = 2vCPU/8GB)."
  type        = string
  default     = "s3-c2-m8"
}

variable "kafka_broker_disk_size" {
  description = "Kafka broker disk size in GB. Min 10 GB."
  type        = number
  default     = 100
}

variable "kafka_clinic_password" {
  description = "Password for Kafka clinic-producer user. Min 8 characters."
  type        = string
  sensitive   = true
}

variable "kafka_fintech_password" {
  description = "Password for Kafka fintech-producer user. Min 8 characters."
  type        = string
  sensitive   = true
}

variable "kafka_consumer_password" {
  description = "Password for Kafka data-consumer user. Min 8 characters."
  type        = string
  sensitive   = true
}

# ─── PostgreSQL ───────────────────────────────────────────────────────────────

variable "postgresql_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "15"

  validation {
    condition     = contains(["14", "15", "16"], var.postgresql_version)
    error_message = "postgresql_version must be 14, 15, or 16."
  }
}

variable "clinic_db_preset" {
  description = "Resource preset for Clinic domain PostgreSQL cluster."
  type        = string
  default     = "s3-c2-m8"  # 2 vCPU, 8 GB RAM
}

variable "clinic_db_disk_size" {
  description = "Disk size for Clinic PostgreSQL cluster in GB."
  type        = number
  default     = 50
}

variable "clinic_db_password" {
  description = "Password for clinic_app PostgreSQL user."
  type        = string
  sensitive   = true
}

variable "fintech_db_preset" {
  description = "Resource preset for Fintech domain PostgreSQL cluster. Larger than clinic due to transaction volume."
  type        = string
  default     = "s3-c4-m16"  # 4 vCPU, 16 GB RAM
}

variable "fintech_db_disk_size" {
  description = "Disk size for Fintech PostgreSQL cluster in GB."
  type        = number
  default     = 100
}

variable "fintech_db_password" {
  description = "Password for fintech_app PostgreSQL user."
  type        = string
  sensitive   = true
}

# ─── Bastion Host ─────────────────────────────────────────────────────────────

variable "bastion_image_id" {
  description = "OS image ID for bastion host. Default: Ubuntu 22.04 LTS in Yandex Cloud."
  type        = string
  default     = "fd8smb7fj0n1tqhs7do3"
}

variable "bastion_disk_size" {
  description = "Boot disk size for bastion host in GB."
  type        = number
  default     = 20
}

variable "bastion_cores" {
  description = "Number of vCPUs for the bastion host."
  type        = number
  default     = 2
}

variable "bastion_memory" {
  description = "RAM for the bastion host in GB."
  type        = number
  default     = 2
}

variable "bastion_ssh_public_key" {
  description = "SSH public key (contents of id_rsa.pub or similar) for bastion and K8s node access."
  type        = string
}

# ─── Kubernetes ───────────────────────────────────────────────────────────────

variable "k8s_version" {
  description = "Kubernetes version for cluster and node groups."
  type        = string
  default     = "1.28"
}

variable "k8s_node_cores" {
  description = "vCPUs for general-purpose Kubernetes nodes."
  type        = number
  default     = 4
}

variable "k8s_node_memory" {
  description = "RAM in GB for general-purpose Kubernetes nodes."
  type        = number
  default     = 8
}

variable "k8s_node_disk_size" {
  description = "Boot disk size in GB for Kubernetes nodes (both node groups)."
  type        = number
  default     = 64
}

variable "k8s_node_min" {
  description = "Minimum number of nodes in the general-purpose node group."
  type        = number
  default     = 1
}

variable "k8s_node_max" {
  description = "Maximum number of nodes in the general-purpose node group."
  type        = number
  default     = 5
}

variable "k8s_node_initial" {
  description = "Initial number of nodes when node group is created."
  type        = number
  default     = 2
}

variable "k8s_ai_node_cores" {
  description = "vCPUs for AI/ML workload Kubernetes nodes."
  type        = number
  default     = 8
}

variable "k8s_ai_node_memory" {
  description = "RAM in GB for AI/ML workload Kubernetes nodes."
  type        = number
  default     = 32
}

variable "k8s_ai_node_max" {
  description = "Maximum number of AI/ML nodes. Scales from 0 (no cost when idle)."
  type        = number
  default     = 3
}
