# This template builds a Longshot application instance, with
# database, queue, caching, and storage resources. Be sure to
# set the application's required SSM parameters before
# provisioning a new application as well:
#   - /{name}/rds/username
#   - /{name}/rds/password
#   - /mandrill/api-key

# Required variables:
variable "environment" {
  description = "The environment for this applicaiton: development, qa, or production."
}

variable "pipeline" {
  description = "The Heroku pipeline ID this application should be created in."
}

variable "name" {
  description = "The application name."
}

variable "host" {
  description = "The hostname this application will be accessible at, e.g. longshot.dosomething.org"
}

variable "email_name" {
  description = "The default 'from' name for this application's mail driver."
}

variable "email_address" {
  description = "The default email address for this application's mail driver."
}

variable "papertrail_destination" {
  description = "The Papertrail log destination for this application."
}

# Optional variables:
variable "web_size" {
  description = "The Heroku dyno type for web processes."
  default     = "Standard-1X"
}

variable "web_scale" {
  description = "The number of web dynos this application should have."
  default     = "1"
}

variable "queue_size" {
  description = "The Heroku dyno type for queue processes."
  default     = "Standard-1X"
}

variable "queue_scale" {
  description = "The number of queue dynos this application should have."
  default     = "1"
}

variable "redis_type" {
  description = "The Heroku Redis add-on plan. See: https://goo.gl/3v3RXX"
  default     = "hobby-dev"
}

variable "database_type" {
  description = "The RDS instance class. See: https://goo.gl/vTMqx9"
  default     = "db.t2.medium"
}

variable "database_subnet_group" {
  description = "The AWS subnet group name for this database."
  default     = "default-vpc-7899331d"
}

variable "database_security_group" {
  description = "The security group ID for this database."
  default     = "sg-c9a37db2"
}

variable "database_size_gb" {
  description = "The amount of storage to allocate to the database, in GB."
  default     = 100
}

data "aws_ssm_parameter" "database_username" {
  name = "/${var.name}/rds/username"
}

data "aws_ssm_parameter" "database_password" {
  name = "/${var.name}/rds/password"
}

data "aws_ssm_parameter" "mandrill_api_key" {
  name = "/mandrill/api-key"
}

# ----------------------------------------------------

resource "heroku_app" "app" {
  name   = "${var.name}"
  region = "us"

  organization {
    name = "dosomething"
  }

  config_vars {
    # App settings:
    APP_ENV                    = "${var.environment}"
    APP_DEBUG                  = "false"
    APP_LOG                    = "errorlog"
    APP_URL                    = "https://${var.host}"
    TRUSTED_PROXY_IP_ADDRESSES = "**"

    # Drivers:
    QUEUE_DRIVER   = "sqs"
    CACHE_DRIVER   = "redis"
    SESSION_DRIVER = "redis"
    STORAGE_DRIVER = "s3"
    MAIL_DRIVER    = "mandrill"

    # Email:
    EMAIL_NAME      = "${var.email_name}"
    EMAIL_ADDRESS   = "${var.email_address}"
    MAIL_HOST       = "smtp.mandrillapp.com"
    MANDRILL_APIKEY = "${data.aws_ssm_parameter.mandrill_api_key.value}"

    # Database:
    DB_HOST     = "${aws_db_instance.database.address}"
    DB_PORT     = "${aws_db_instance.database.port}"
    DB_DATABASE = "${aws_db_instance.database.name}"
    DB_USERNAME = "${data.aws_ssm_parameter.database_username.value}"
    DB_PASSWORD = "${data.aws_ssm_parameter.database_password.value}"

    # S3 Bucket & SQS Queue:
    AWS_ACCESS_KEY    = "${aws_iam_access_key.aws_key.id}"
    AWS_SECRET_KEY    = "${aws_iam_access_key.aws_key.secret}"
    SQS_DEFAULT_QUEUE = "${aws_sqs_queue.queue.id}"
    S3_REGION         = "${aws_s3_bucket.storage.region}"
    S3_BUCKET         = "${aws_s3_bucket.storage.id}"

    # Additional secrets, set manually:
    # APP_KEY = ...
  }

  buildpacks = [
    "heroku/nodejs",
    "heroku/php",
  ]

  acm = true
}

resource "heroku_formation" "web" {
  app      = "${heroku_app.app.name}"
  type     = "web"
  size     = "${var.web_size}"
  quantity = "${var.web_scale}"
}

resource "heroku_formation" "queue" {
  app      = "${heroku_app.app.name}"
  type     = "queue"
  size     = "${var.queue_size}"
  quantity = "${var.queue_scale}"
}

resource "heroku_domain" "domain" {
  app      = "${heroku_app.app.name}"
  hostname = "${var.host}"
}

resource "heroku_drain" "papertrail" {
  app = "${heroku_app.app.name}"
  url = "syslog+tls://${var.papertrail_destination}"
}

resource "heroku_pipeline_coupling" "app" {
  app      = "${heroku_app.app.name}"
  pipeline = "${var.pipeline}"

  # Heroku uses "staging" for what we call "qa":
  stage = "${var.environment == "qa" ? "staging" : var.environment}"
}

resource "heroku_addon" "redis" {
  app  = "${heroku_app.app.name}"
  plan = "heroku-redis:${var.redis_type}"
}

resource "aws_db_instance" "database" {
  identifier = "${var.name}"
  name       = "longshot"

  engine            = "mariadb"
  engine_version    = "10.3"
  instance_class    = "${var.database_type}"
  allocated_storage = "${var.database_size_gb}"

  allow_major_version_upgrade = true

  backup_retention_period = 7             # 7 days.
  backup_window           = "06:00-07:00" # 1-2am ET.

  username = "${data.aws_ssm_parameter.database_username.value}"
  password = "${data.aws_ssm_parameter.database_password.value}"

  # TODO: We should migrate our account out of EC2-Classic, create
  # a default VPC, and let resources be created in there by default!
  db_subnet_group_name = "${var.database_subnet_group}"

  vpc_security_group_ids = ["${var.database_security_group}"]
  publicly_accessible    = true

  tags = {
    Application = "${var.name}"
  }
}

resource "aws_sqs_queue" "queue" {
  name                      = "${var.name}"
  message_retention_seconds = "${60 * 60 * 24 * 14}" # 14 days (maximum).
}

resource "aws_s3_bucket" "storage" {
  bucket = "${var.name}"
  acl    = "public-read"

  tags {
    Application = "${var.name}"
  }
}

resource "aws_iam_user" "aws_user" {
  name = "${var.name}"
}

resource "aws_iam_access_key" "aws_key" {
  user = "${aws_iam_user.aws_user.name}"
}

data "template_file" "sqs_policy" {
  template = "${file("${path.root}/shared/sqs-policy.json.tpl")}"

  vars {
    queue_arn = "${aws_sqs_queue.queue.arn}"
  }
}

resource "aws_iam_user_policy" "sqs_policy" {
  name   = "${var.name}-sqs"
  user   = "${aws_iam_user.aws_user.name}"
  policy = "${data.template_file.sqs_policy.rendered}"
}

data "template_file" "s3_policy" {
  template = "${file("${path.root}/shared/s3-policy.json.tpl")}"

  vars {
    bucket_arn = "${aws_s3_bucket.storage.arn}"
  }
}

resource "aws_iam_user_policy" "s3_policy" {
  name   = "${var.name}-s3"
  user   = "${aws_iam_user.aws_user.name}"
  policy = "${data.template_file.s3_policy.rendered}"
}

output "name" {
  value = "${heroku_app.app.name}"
}

output "domain" {
  value = "${heroku_domain.domain.hostname}"
}

output "backend" {
  value = "${heroku_app.app.heroku_hostname}"
}