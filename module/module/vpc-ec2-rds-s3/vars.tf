variable "cidr_block" {
  default = "10.0.0.0/16"
}

variable "product_name" {}

variable "azs" {
  type = list(string)
  default = [
    "us-east-1a",
    "us-east-1b",
  ]
}

variable "pub_subnet_mask" {
  default = "24"
}

variable "pvt_subnet_mask" {
  default = "24"
}

variable "data_subnet_mask" {
  default = "24"
}

variable "create_pvt_nat" {
  default = true
}

variable "create_data_nat" {
  default = true
}

variable "create_flow_logs" {
  default = true
}

variable "flow_logs_destination" {
  default = "cloud-watch-logs"
}

variable "flow_logs_cw_log_group_arn" {
  default = ""
}

variable "flow_logs_bucket_arn" {
  default = ""
}

variable "create_sgs" {
  default = false
}

variable "tags" {
  type    = map(any)
  default = {}
}

variable "add_eks_tags" {
  default = false
}

variable "tg_health_check_matcher" {
  default = 200
}

variable "tg_health_check_path" {
  default = "/"
  type = string
}

variable "tg_health_check_interval" {
  default = 30
}

variable "tg_health_check_timeout" {
  default = 5
}

variable "tg_deregistration_delay" {
  default = 100
}

variable "ami_id" {
  type = string
}

variable "nlb_public_inbound_cidr" {
  type = list(string)
}

variable "instance_type" {}
variable "key_name" {}
variable "nlb_to_application_port" {}

variable "user_data_path" {
  type = string
}

variable "asg_max_capacity" {
  default = 1
}

variable "asg_min_capacity" {
  default = 1
}

variable "asg_desired_capacity" {
  default = 1
}

variable "rds_identifier" {
  type = string
}

variable "rds_engine" {
  type = string
}

variable "rds_engine_version" {
  type = string
}

variable "rds_instance_class" {
  type = string
}

variable "rds_allocated_storage" {
  default = 5
}

variable "rds_master_username" {
  type = string
}

variable "rds_master_password" {
  type = string
  sensitive   = true
}

variable "rds_port" {
}

variable "rds_auth_enabled" {
  type = bool
  default = false
}

variable "rds_parameters" {
  type = list(any)
  default = []
}

variable "rds_options" {
  type = list(any)
  default = []
}

variable "rds_major_engine_version" {
  type = string
}

variable "rds_family" {
  type = string
}

variable "create_bucket" {
  description = "Controls if S3 bucket should be created"
  type        = bool
  default     = true
}

variable "bucket" {
  description = "(Optional, Forces new resource) The name of the bucket. If omitted, Terraform will assign a random, unique name."
  type        = string
  default     = null
}

variable "bucket_prefix" {
  description = "(Optional, Forces new resource) Creates a unique bucket name beginning with the specified prefix. Conflicts with bucket."
  type        = string
  default     = null
}

variable "acl" {
  description = "(Optional) The canned ACL to apply. Defaults to 'private'. Conflicts with `grant`"
  type        = string
  default     = "private"
}

variable "force_destroy" {
  description = "(Optional, Default:false ) A boolean that indicates all objects should be deleted from the bucket so that the bucket can be destroyed without error. These objects are not recoverable."
  type        = bool
  default     = false
}

variable "acceleration_status" {
  description = "(Optional) Sets the accelerate configuration of an existing bucket. Can be Enabled or Suspended."
  type        = string
  default     = null
}

variable "request_payer" {
  description = "(Optional) Specifies who should bear the cost of Amazon S3 data transfer. Can be either BucketOwner or Requester. By default, the owner of the S3 bucket would incur the costs of any data transfer. See Requester Pays Buckets developer guide for more information."
  type        = string
  default     = null
}

variable "website" {
  description = "Map containing static web-site hosting or redirect configuration."
  type        = map(string)
  default     = {}
}

variable "cors_rule" {
  description = "List of maps containing rules for Cross-Origin Resource Sharing."
  type        = any
  default     = []
}

variable "versioning" {
  description = "Map containing versioning configuration."
  type        = map(string)
  default     = {}
}

variable "logging" {
  description = "Map containing access bucket logging configuration."
  type        = map(string)
  default     = {}
}

variable "grant" {
  description = "An ACL policy grant. Conflicts with `acl`"
  type        = any
  default     = []
}

variable "lifecycle_rule" {
  description = "List of maps containing configuration of object lifecycle management."
  type        = any
  default     = []
}

variable "replication_configuration" {
  description = "Map containing cross-region replication configuration."
  type        = any
  default     = {}
}

variable "server_side_encryption_configuration" {
  description = "Map containing server-side encryption configuration."
  type        = any
  default     = {}
}


variable "object_lock_configuration" {
  description = "Map containing S3 object locking configuration."
  type        = any
  default     = {}
}