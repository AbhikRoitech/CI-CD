# ----- Provider / general -----
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name (dev/stage/prod)"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name, used in identifiers/tags"
  type        = string
  default     = "learning-rds"
}

# ----- Engine -----
variable "engine" {
  description = "Database engine"
  type        = string
  default     = "postgres"
}

variable "engine_version" {
  description = "Engine version"
  type        = string
  default     = "16.4"
}

# ----- Instance -----
variable "instance_class" {
  description = "RDS instance class (use *.micro for free tier)"
  type        = string
  default     = "db.t3.micro"
}

# ----- Storage -----
variable "allocated_storage" {
  description = "Initial storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Max autoscaling storage; set = allocated_storage to disable"
  type        = number
  default     = 20
}

variable "storage_type" {
  description = "Storage type (gp2 for free tier)"
  type        = string
  default     = "gp2"
}

variable "storage_encrypted" {
  description = "Encrypt storage with KMS default key"
  type        = bool
  default     = true
}

# ----- Database -----
variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "devdb"
}

variable "db_username" {
  description = "Master username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Master password (prefer TF_VAR_db_password env var)"
  type        = string
  sensitive   = true
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

# ----- HA / cost controls -----
variable "multi_az" {
  description = "Multi-AZ deployment (not free tier)"
  type        = bool
  default     = false
}

variable "publicly_accessible" {
  description = "Assign a public IP so you can connect from outside the VPC"
  type        = bool
  default     = true
}

# ----- Backups & maintenance -----
variable "backup_retention_period" {
  description = "Days to keep automated backups (0 disables)"
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Daily backup window (UTC)"
  type        = string
  default     = "18:00-18:30"
}

variable "maintenance_window" {
  description = "Weekly maintenance window (UTC)"
  type        = string
  default     = "Sun:18:45-Sun:19:15"
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Block terraform destroy when true"
  type        = bool
  default     = false
}

# ----- Networking -----
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach the DB port"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ----- Tags -----
variable "tags" {
  description = "Common tags applied to resources"
  type        = map(string)
  default     = {}
}
