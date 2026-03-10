###############################################################################
# outputs.tf — «Будущее 2.0» Key Infrastructure Parameters
###############################################################################

# ─── Network ──────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "VPC (Network) ID"
  value       = yandex_vpc_network.main.id
}

output "vpc_name" {
  description = "VPC (Network) name"
  value       = yandex_vpc_network.main.name
}

output "subnet_ids" {
  description = "Map of all subnet IDs by tier name"
  value = {
    mgmt_a = yandex_vpc_subnet.mgmt_a.id
    app_a  = yandex_vpc_subnet.app_a.id
    app_b  = yandex_vpc_subnet.app_b.id
    data_a = yandex_vpc_subnet.data_a.id
    data_b = yandex_vpc_subnet.data_b.id
  }
}

output "nat_gateway_id" {
  description = "NAT Gateway ID for private subnet egress"
  value       = yandex_vpc_gateway.nat.id
}

# ─── Security Groups ──────────────────────────────────────────────────────────

output "security_group_ids" {
  description = "Map of security group IDs by role"
  value = {
    bastion    = yandex_vpc_security_group.bastion.id
    kafka      = yandex_vpc_security_group.kafka.id
    postgresql = yandex_vpc_security_group.postgresql.id
    k8s        = yandex_vpc_security_group.k8s.id
  }
}

# ─── Bastion Host ─────────────────────────────────────────────────────────────

output "bastion_public_ip" {
  description = "Public IP address of the bastion host (use for SSH)"
  value       = yandex_compute_instance.bastion.network_interface[0].nat_ip_address
}

output "bastion_internal_ip" {
  description = "Internal IP address of the bastion host"
  value       = yandex_compute_instance.bastion.network_interface[0].ip_address
}

output "bastion_ssh_command" {
  description = "SSH command to connect to the bastion host"
  value       = "ssh ubuntu@${yandex_compute_instance.bastion.network_interface[0].nat_ip_address}"
}

# ─── Data Lakehouse ───────────────────────────────────────────────────────────

output "lakehouse_bucket_name" {
  description = "Name of the Data Lakehouse S3-compatible bucket"
  value       = yandex_storage_bucket.lakehouse.bucket
}

output "lakehouse_bucket_domain" {
  description = "FQDN of the Lakehouse bucket for S3 API access"
  value       = yandex_storage_bucket.lakehouse.bucket_domain_name
}

output "lakehouse_s3_endpoint" {
  description = "S3 API endpoint for Lakehouse access (use with AWS CLI / dbt-spark)"
  value       = "https://storage.yandexcloud.net"
}

output "lakehouse_access_key_id" {
  description = "Access Key ID for Lakehouse Object Storage (S3 API)"
  value       = yandex_iam_service_account_static_access_key.storage_key.access_key
  sensitive   = true
}

output "lakehouse_secret_key" {
  description = "Secret Access Key for Lakehouse Object Storage (S3 API)"
  value       = yandex_iam_service_account_static_access_key.storage_key.secret_key
  sensitive   = true
}

# ─── Kafka ────────────────────────────────────────────────────────────────────

output "kafka_cluster_id" {
  description = "Managed Kafka cluster ID"
  value       = yandex_mdb_kafka_cluster.main.id
}

output "kafka_broker_fqdns" {
  description = "Kafka broker FQDNs for bootstrap-servers configuration"
  value = [
    for host in yandex_mdb_kafka_cluster.main.host : host.fqdn
  ]
}

output "kafka_topics" {
  description = "List of created Kafka topic names"
  value = [
    yandex_mdb_kafka_topic.clinic_visits.name,
    yandex_mdb_kafka_topic.fintech_payments.name,
    yandex_mdb_kafka_topic.fintech_loans.name,
    yandex_mdb_kafka_topic.ai_inference.name,
    yandex_mdb_kafka_topic.pharma_catalog.name,
  ]
}

# ─── PostgreSQL: Clinic ───────────────────────────────────────────────────────

output "clinic_db_cluster_id" {
  description = "Clinic domain PostgreSQL cluster ID"
  value       = yandex_mdb_postgresql_cluster.clinic.id
}

output "clinic_db_hosts" {
  description = "Clinic PostgreSQL host FQDNs (primary and replica)"
  value = [
    for host in yandex_mdb_postgresql_cluster.clinic.host : host.fqdn
  ]
}

output "clinic_db_name" {
  description = "Clinic operational database name"
  value       = yandex_mdb_postgresql_database.clinic_db.name
}

output "clinic_db_user" {
  description = "Clinic database application user"
  value       = yandex_mdb_postgresql_user.clinic_app.name
}

output "clinic_db_connection_string" {
  description = "Clinic DB connection string template (replace host with actual FQDN)"
  value       = "postgresql://clinic_app:<password>@<clinic_host>:5432/clinic_operational?sslmode=require"
}

# ─── PostgreSQL: Fintech ──────────────────────────────────────────────────────

output "fintech_db_cluster_id" {
  description = "Fintech domain PostgreSQL cluster ID"
  value       = yandex_mdb_postgresql_cluster.fintech.id
}

output "fintech_db_hosts" {
  description = "Fintech PostgreSQL host FQDNs (primary and replica)"
  value = [
    for host in yandex_mdb_postgresql_cluster.fintech.host : host.fqdn
  ]
}

output "fintech_db_name" {
  description = "Fintech core database name"
  value       = yandex_mdb_postgresql_database.fintech_db.name
}

output "fintech_db_user" {
  description = "Fintech database application user"
  value       = yandex_mdb_postgresql_user.fintech_app.name
}

# ─── Kubernetes ───────────────────────────────────────────────────────────────

output "k8s_cluster_id" {
  description = "Kubernetes cluster ID"
  value       = yandex_kubernetes_cluster.main.id
}

output "k8s_cluster_endpoint" {
  description = "Kubernetes API server internal endpoint"
  value       = yandex_kubernetes_cluster.main.master[0].internal_v4_endpoint
}

output "k8s_get_credentials_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "yc managed-kubernetes cluster get-credentials ${yandex_kubernetes_cluster.main.id} --internal"
}

output "k8s_node_groups" {
  description = "Kubernetes node group IDs"
  value = {
    general = yandex_kubernetes_node_group.general.id
    ai      = yandex_kubernetes_node_group.ai.id
  }
}

# ─── IAM ──────────────────────────────────────────────────────────────────────

output "service_account_ids" {
  description = "Service account IDs"
  value = {
    k8s     = yandex_iam_service_account.k8s.id
    storage = yandex_iam_service_account.storage.id
  }
}

# ─── Summary ──────────────────────────────────────────────────────────────────

output "deployment_summary" {
  description = "Human-readable deployment summary"
  value = <<-EOT

    ═══════════════════════════════════════════════════════
     «Будущее 2.0» — Infrastructure Deployment Summary
    ═══════════════════════════════════════════════════════
     Environment  : ${var.environment}
     Project      : ${var.project_name}
     Region       : ru-central1

    ── Access ───────────────────────────────────────────
     Bastion SSH  : ssh ubuntu@${yandex_compute_instance.bastion.network_interface[0].nat_ip_address}

    ── Data Platform ────────────────────────────────────
     Lakehouse    : s3://${yandex_storage_bucket.lakehouse.bucket}
     Kafka topics : clinic.visit.events, fintech.payment.events,
                    fintech.loan.events, ai.inference.results,
                    partner.pharma.catalog

    ── Databases ────────────────────────────────────────
     Clinic DB    : clinic_operational @ PostgreSQL ${var.postgresql_version}
     Fintech DB   : fintech_core @ PostgreSQL ${var.postgresql_version}

    ── Kubernetes ───────────────────────────────────────
     Cluster      : ${yandex_kubernetes_cluster.main.name}
     Node Groups  : general (${var.k8s_node_min}–${var.k8s_node_max} nodes)
                    ai (0–${var.k8s_ai_node_max} nodes, scale-to-zero)

    ── Get kubeconfig ───────────────────────────────────
     yc managed-kubernetes cluster get-credentials \
       ${yandex_kubernetes_cluster.main.id} --internal
    ═══════════════════════════════════════════════════════
  EOT
}
