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
  description = "Project name, used as a prefix in names/tags"
  type        = string
  default     = "todo-secure"
}

# ----- Networking -----
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability Zones to spread the subnets across (must be exactly 2 for this design)"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

# ----- Tags -----
variable "tags" {
  description = "Common tags applied to every resource via provider default_tags"
  type        = map(string)
  default = {
    Project     = "todo-secure"
    Environment = "dev"
    ManagedBy   = "terraform"
    Owner       = "AbhikIAM"
  }
}
