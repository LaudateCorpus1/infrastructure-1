variable "graphql_pipeline" {}
variable "northstar_pipeline" {}
variable "phoenix_pipeline" {}
variable "rogue_pipeline" {}
variable "papertrail_destination" {}
variable "papertrail_destination_fastly" {}

module "fastly-frontend" {
  source = "fastly-frontend"

  ashes_backend = "${module.ashes.backend}"

  phoenix_name    = "${module.phoenix.name}"
  phoenix_backend = "${module.phoenix.backend}"

  papertrail_destination = "${var.papertrail_destination_fastly}"
}

module "fastly-backend" {
  source = "fastly-backend"

  graphql_name    = "${module.graphql.name}"
  graphql_domain  = "${module.graphql.domain}"
  graphql_backend = "${module.graphql.backend}"

  northstar_name    = "${module.northstar.name}"
  northstar_domain  = "${module.northstar.domain}"
  northstar_backend = "${module.northstar.backend}"

  phoenix_name    = "${module.phoenix.name}"
  phoenix_domain  = "${module.phoenix.domain}"
  phoenix_backend = "${module.phoenix.backend}"

  rogue_name    = "${module.rogue.name}"
  rogue_domain  = "${module.rogue.domain}"
  rogue_backend = "${module.rogue.backend}"

  papertrail_destination = "${var.papertrail_destination_fastly}"
}

module "graphql" {
  source = "graphql"

  graphql_pipeline       = "${var.graphql_pipeline}"
  papertrail_destination = "${var.papertrail_destination}"
}

module "northstar" {
  source = "../applications/northstar"

  environment            = "qa"
  name                   = "dosomething-northstar-qa"
  domain                 = "identity-qa.dosomething.org"
  pipeline               = "${var.northstar_pipeline}"
  papertrail_destination = "${var.papertrail_destination}"
}

module "phoenix" {
  source = "phoenix"

  phoenix_pipeline       = "${var.phoenix_pipeline}"
  papertrail_destination = "${var.papertrail_destination}"
}

module "rogue" {
  source = "../applications/rogue"

  environment            = "qa"
  name                   = "dosomething-rogue-qa"
  domain                 = "activity-qa.dosomething.org"
  pipeline               = "${var.rogue_pipeline}"
  papertrail_destination = "${var.papertrail_destination}"
}

module "ashes" {
  source = "ashes"
}
