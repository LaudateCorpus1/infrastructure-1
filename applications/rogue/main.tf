# This template builds a Rogue application instance.
#
# Manual setup steps:
#   - Set 'APP_KEY' by running 'php artisan generate:key'.
#   - Set 'ROGUE_API_KEY' to a random string for this instance's v2 API key.
#   - Create app-specific user & machine OAuth clients (via Aurora) and set the
#     values for 'NORTHSTAR_URL', 'NORTHSTAR_AUTH_ID', 'NORTHSTAR_AUTH_SECRET',
#      'NORTHSTAR_CLIENT_ID', and 'NORTHSTAR_CLIENT_SECRET'
#   - Set 'BLINK_URL', 'BLINK_USERNAME', and 'BLINK_PASSWORD' if using
#     Blink, and set 'DS_ENABLE_BLINK' environment variable to 'true'.
#   - Set 'DS_ENABLE_BLINK', 'DS_ENABLE_GLIDE', 'DS_ENABLE_PUSH_TO_QUASAR',
#     'DS_ENABLE_V3_QUANTITY_SUPPORT', 'FASTLY_API_TOKEN', 'FASTLY_SERVICE_ID',
#     'FASTLY_URL', 'SLACK_ENDPOINT', and 'SLACK_WEBHOOK_INTEGRATION_URL'.
#   - Finally, set '/newrelic/api-key' in SSM to the New Relic API Key, if using.
#
# NOTE: We'll move more of these steps into Terraform over time!

# Required variables:
variable "environment" {
  description = "The environment for this application: development, qa, or production."
}

variable "pipeline" {
  description = "The Heroku pipeline ID this application should be created in."
}

variable "domain" {
  description = "The domain this application will be accessible at, e.g. activity.dosomething.org"
}

variable "name" {
  description = "The application name."
}

variable "papertrail_destination" {
  description = "The Papertrail log destination for this application."
}

variable "with_newrelic" {
  # See usage below for default fallback. <https://stackoverflow.com/a/51758050/811624>
  description = "Should New Relic be enabled for this app? Enabled by default on prod."
  default     = ""
}

locals {}

module "app" {
  source = "../../shared/laravel_app"

  name        = "${var.name}"
  domain      = "${var.domain}"
  pipeline    = "${var.pipeline}"
  environment = "${var.environment}"

  web_size  = "${var.environment == "production" ? "Standard-2x" : "Standard-1x"}"
  web_scale = "${var.environment == "production" ? 2 : 1}"

  # TODO: Add 'module.database.config_vars' once we've migrated
  # records over to the new database instance.
  # TODO: Add 'module.storage.config_vars' once we've migrated
  # files over to the new storage bucket.
  # TODO: Add 'module.queue.config_vars' once we've updated this
  # application to use the new IAM environment variables set below.
  config_vars = "${merge(
    module.iam_user.config_vars,
  )}"

  # We don't run a queue process on development right now. @TODO: Should we?
  queue_scale = "${var.environment == "development" ? 0 : 1}"

  with_redis = true

  papertrail_destination = "${var.papertrail_destination}"
  with_newrelic          = "${coalesce(var.with_newrelic, var.environment == "production")}"
}

module "database" {
  source = "../../shared/mariadb_instance"

  name           = "${var.name}"
  environment    = "${var.environment}"
  instance_class = "${var.environment == "production" ? "db.m4.large" : "db.t2.medium"}"
  multi_az       = "${var.environment == "production"}"
}

module "iam_user" {
  source = "../../shared/iam_app_user"
  name   = "${var.name}"
}

module "queue" {
  source = "../../shared/sqs_queue"
  name   = "${var.name}"
  user   = "${module.iam_user.name}"
}

module "storage" {
  source = "../../shared/s3_bucket"
  name   = "${var.name}"
  user   = "${module.iam_user.name}"

  force_public = true
}

output "name" {
  value = "${var.name}"
}

output "domain" {
  value = "${var.domain}"
}

output "backend" {
  value = "${module.app.backend}"
}
