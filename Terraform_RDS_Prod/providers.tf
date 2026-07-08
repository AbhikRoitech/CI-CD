provider "aws" {
  region = var.aws_region

  # Applied automatically to every resource that supports tagging — so you never
  # forget to tag something. Per-resource tags merge on top of these.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
