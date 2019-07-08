# frozen_string_literal: true

require "yaml"
require "./setup/helpers/abs_helper.rb"
include AbsHelper # rubocop:disable Style/MixinUsage

# TODO: specify via env variable, arg, options file, etc?
# currently uses ARGV[0], ARGV[1] if specified, otherwise these defaults
ABS_ID = "slv"
OUTPUT_DIR = "./"

TEMPLATE_DIR = "./util/abs/templates"

# TODO: allow different sizes for each node?
ABS_SIZE = "c5.2xlarge"
ABS_VOLUME_SIZE = "80"

ROLES_CORE = %w[master
                puppet_db
                compiler_a
                compiler_b].freeze

ROLES_HA = %w[master_replica
              puppet_db_replica].freeze

# TODO: specify as env variable or arg?
ROLES = ROLES_CORE + ROLES_HA

# TODO: move to spec when test cases are implemented
# for now this allows testing of the create_pe_xl_bolt_files method without provisioning
TEST_HOSTS_HA = [{ role: "puppet_db", hostname: "ip-10-227-3-22.amz-dev.puppet.net" },
                 { role: "compiler_b", hostname: "ip-10-227-1-195.amz-dev.puppet.net" },
                 { role: "puppet_db_replica", hostname: "ip-10-227-3-158.amz-dev.puppet.net" },
                 { role: "master", hostname: "ip-10-227-3-127.amz-dev.puppet.net" },
                 { role: "compiler_a", hostname: "ip-10-227-3-242.amz-dev.puppet.net" },
                 { role: "master_replica", hostname: "ip-10-227-1-82.amz-dev.puppet.net" }].freeze

TEST_HOSTS_NO_HA = [{ role: "puppet_db", hostname: "ip-10-227-3-22.amz-dev.puppet.net" },
                    { role: "compiler_b", hostname: "ip-10-227-1-195.amz-dev.puppet.net" },
                    { role: "master", hostname: "ip-10-227-3-127.amz-dev.puppet.net" },
                    { role: "compiler_a", hostname: "ip-10-227-3-242.amz-dev.puppet.net" }].freeze

NODES_YAML = <<~NODES_YAML
  ---
  groups:
    - name: pe_xl_nodes
      config:
        transport: ssh
        ssh:
          host-key-check: false
          user: centos
          run-as: root
          tty: true
NODES_YAML

# Creates the Bolt inventory file (nodes.yaml) and
# parameters file (params.json) for the specified hosts
#
# Note: designed to use the output of provision_hosts_for_roles
#
# @author Bill Claytor
#
# @param [Array<Hash>] hosts The provisioned hosts
# @param [String] output_dir The directory where the file should be written
#
# @example
#   hosts = provision_hosts_for_roles(roles)
#   create_pe_xl_bolt_files(hosts)
#
# TODO: move to abs_helper or elsewhere?
# TODO: spec test(s)
def create_pe_xl_bolt_files(hosts, output_dir)
  create_nodes_yaml(hosts, output_dir)
  create_params_json(hosts, output_dir)
end

# Creates the Bolt inventory file (nodes.yaml) for the specified hosts
#
# Note: designed to use the output of provision_hosts_for_roles
#
# @author Bill Claytor
#
# @param [Array<Hash>] hosts The provisioned hosts
# @param [String] output_dir The directory where the file should be written
#
# @example
#   hosts = provision_hosts_for_roles(roles)
#   create_nodes_yaml(hosts, output_dir)
def create_nodes_yaml(hosts, output_dir)
  yaml = YAML.safe_load NODES_YAML
  nodes = []

  hosts.each do |host|
    nodes << host[:hostname]
  end

  yaml["groups"][0]["nodes"] = nodes
  File.write("#{output_dir}/nodes.yaml", YAML.dump(yaml))
end

# Checks the nodes.yaml file to ensure it has been written correctly
#
# @author Bill Claytor
#
# @param [String] output_dir The directory where the file should be written
#
# @example
#   check_nodes_yaml(output_dir)
def check_nodes_yaml(output_dir)
  file = "#{output_dir}/nodes.yaml"
  puts "Checking #{file}"

  yaml = YAML.load_file file
  nodes = yaml["groups"][0]["nodes"]

  puts
  puts "nodes:"
  puts nodes
  puts
end

# Creates the Bolt parameters file (params.json) for the specified hosts
#
# Note: designed to use the output of provision_hosts_for_roles
#
# @author Bill Claytor
#
# @param [Array<Hash>] hosts The provisioned hosts
# @param [String] output_dir The directory where the file should be written
#
# @example
#   hosts = provision_hosts_for_roles(roles)
#   create_params_json(hosts, output_dir)
def create_params_json(hosts, output_dir)
  # HA?
  master_replica = hosts.detect { |m| m[:role] == "master_replica" }
  suffix = if master_replica
             "ha"
           else
             "no_ha"
           end

  params_json = File.read("#{TEMPLATE_DIR}/params_#{suffix}.json")

  # replace parameters for each host
  hosts.each do |host|
    hostname = host[:hostname]
    role = host[:role]
    param = "$#{role.upcase}$"

    puts "Replacing parameters: "
    puts " hostname: #{hostname}"
    puts " role: #{role}"
    puts " parameter: #{param}"
    puts

    # replace parameters
    params_json = params_json.gsub(param, hostname)
  end

  File.write("#{output_dir}/params.json", params_json)
end

abs_id = ARGV[0] || ABS_ID
output_dir = ARGV[1] || "./"

# TODO: update provision_hosts_for_roles to generate last_abs_resource_hosts.log
# and generate Beaker hosts file
hosts = provision_hosts_for_roles(ROLES, abs_id, ABS_SIZE, ABS_VOLUME_SIZE)
create_pe_xl_bolt_files(hosts, output_dir)
