# ───────────────────────── Provider / naming ─────────────────────────
variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name; used in resource names and tags."
  type        = string
  default     = "learning-rds"
}

variable "environment" {
  description = "Environment name; used in resource names and tags."
  type        = string
  default     = "prod"
}

# ───────────────────────── Networking ─────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the private DB subnets. Provide at least 2 (different AZs) for Multi-AZ."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "app_ingress_cidrs" {
  description = "Optional extra CIDRs allowed to reach the DB (e.g. a VPN range). The app security group is always allowed."
  type        = list(string)
  default     = []
}

# ───────────────────────── Engine ─────────────────────────
variable "engine" {
  description = "Database engine."
  type        = string
  default     = "postgres"
}

variable "engine_version" {
  description = "Engine major version. Use just the major (e.g. \"16\") to let RDS pick the latest supported minor."
  type        = string
  default     = "16"
}

variable "parameter_group_family" {
  description = "Parameter group family; must match the engine major version."
  type        = string
  default     = "postgres16"
}

# ───────────────────────── Instance / storage ─────────────────────────
variable "instance_class" {
  description = "RDS instance class. Prod should be at least db.t3.medium; larger for real load."
  type        = string
  default     = "db.t3.medium"
}

variable "allocated_storage" {
  description = "Initial storage in GB."
  type        = number
  default     = 100
}

variable "max_allocated_storage" {
  description = "Upper bound for storage autoscaling in GB. Must be > allocated_storage to enable autoscaling."
  type        = number
  default     = 500
}

variable "storage_type" {
  description = "Storage type. gp3 is the recommended prod default."
  type        = string
  default     = "gp3"
}

# ───────────────────────── Database ─────────────────────────
variable "db_name" {
  description = "Initial database name created on the instance."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username. The password is generated and stored in Secrets Manager (not set here)."
  type        = string
  default     = "postgres"
}

variable "db_port" {
  description = "Database port."
  type        = number
  default     = 5432
}

# ───────────────────────── High availability ─────────────────────────
variable "multi_az" {
  description = "Multi-AZ deployment for automatic failover. true for production."
  type        = bool
  default     = true
}

# ───────────────────────── Backups & maintenance ─────────────────────────
variable "backup_retention_period" {
  description = "Days of automated backups (enables Point-In-Time Recovery). Prod: 14-35."
  type        = number
  default     = 30
}

variable "backup_window" {
  description = "Daily automated backup window (UTC)."
  type        = string
  default     = "18:00-18:30"
}

variable "maintenance_window" {
  description = "Weekly maintenance window (UTC). Must not overlap the backup window."
  type        = string
  default     = "Sun:18:45-Sun:19:15"
}

# ───────────────────────── Monitoring ─────────────────────────
variable "monitoring_interval" {
  description = "Enhanced Monitoring granularity in seconds (0 disables; 1,5,10,15,30,60 valid)."
  type        = number
  default     = 60
}

variable "performance_insights_retention" {
  description = "Performance Insights retention in days (7 = free tier of PI; 731 = 2 years)."
  type        = number
  default     = 7
}

# ───────────────────────── Safety ─────────────────────────
variable "deletion_protection" {
  description = "Block accidental deletion. true for production."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. false for production (keep the data)."
  type        = bool
  default     = false
}
