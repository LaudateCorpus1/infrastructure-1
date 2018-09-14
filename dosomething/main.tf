variable "graphql_pipeline" {}
variable "northstar_pipeline" {}
variable "papertrail_destination" {}

module "fastly" {
  source = "fastly"

  graphql_name    = "${module.graphql.name}"
  graphql_domain  = "${module.graphql.domain}"
  graphql_backend = "${module.graphql.backend}"
}

module "graphql" {
  source = "graphql"

  graphql_pipeline       = "${var.graphql_pipeline}"
  papertrail_destination = "${var.papertrail_destination}"
}

module "northstar" {
  source = "northstar"

  northstar_pipeline     = "${var.northstar_pipeline}"
  papertrail_destination = "${var.papertrail_destination}"
}
