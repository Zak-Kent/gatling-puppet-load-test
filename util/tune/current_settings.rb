#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

# This script returns a JSON array of the current values for the settings adjusted by the 'pe_tune' module:
#   https://github.com/tkishel/pe_tune
#
# The list of settings can be found here:
#   https://github.com/tkishel/pe_tune/blob/79d5db4ddc7bbf3b1c9aefcdfab7f1dc9b3c3f4e/lib/puppet_x/puppetlabs/tune.rb#L19
#
# The script can be run by either copying it to the master and running from there
# or by using Bolt:
#
#   bolt script run util/tune/current_settings.rb --user root --nodes 10.227.1.146
#
# TODO: spec

require "fileutils"
require "json"

NA = "N/A"
PE_PUPPET_SERVER_CONF = "/etc/puppetlabs/puppetserver/conf.d/pe-puppet-server.conf"
POSTGRES_CONF = Dir.glob("/opt/puppetlabs/server/data/postgresql/*/data/postgresql.conf")[-1]
PUPPET_DB_CONF = "/etc/puppetlabs/puppetdb/conf.d/config.ini"
MIN_DEFAULT_JRUBIES = 1
MAX_DEFAULT_JRUBIES = 4
DEFAULT_EXCLUSION = ""
DEFAULT_WORKING_DIRECTORY = "/root/tmp"
DEFAULT_OUTPUT_FILE = "current_tune_settings.json"

# Returns the value for the 'max-active-instances' parameter if found in the conf file.
# If the conf file doesn't exist returns NA as puppetserver must not be installed on this host.
# Otherwise calculates the default based on the documentation linked above which was current at the
# time this was written.  It could have changed, but probably not.
#
# See the following documentation:
#   https://puppet.com/docs/pe/2019.1/config_puppetserver.html#tune-the-maximum-number-of-jruby-instances
#
# @author Bill Claytor
#
# @return [string] The value for the max-active-instances setting if set, otherwise the default (see link above)
#
# @example
#   value = puppetserver_jruby_max_active_instances
#
def puppetserver_jruby_max_active_instances
  return NA unless File.exist? PE_PUPPET_SERVER_CONF

  conf = File.read(PE_PUPPET_SERVER_CONF)
  match_pattern = /^\s*max-active-instances: (\d+)/
  conf_scan = conf.scan(match_pattern)
  value = conf_scan.last ? conf_scan.last.first : nil
  return value unless value.nil?

  # Since there is no value in the file, the default must be in effect
  calculate_puppetserver_jruby_max_active_instances_default
end

# Calculates the default based on the documentation linked which was current at the
# time this was written.  It could have changed, but probably not.
# This is needed because there is no method to get the actual setting in use from the active process
# If the value isn't set in the conf file, then the internal default is used, which is calculated
# with the documented formula.
#
# See the following documentation:
#   https://puppet.com/docs/pe/2019.1/config_puppetserver.html#tune-the-maximum-number-of-jruby-instances
#
# @author Randell Pelak
#
# @return [string] The default value for the max-active-instances setting
#
def calculate_puppetserver_jruby_max_active_instances_default
  # TODO: eliminate bash
  command = "facter processorcount"
  output = `#{command}`
  return NA unless output # no facter => no puppet => no puppetserver...

  # See the docs link in the description above
  # The default used in PE is the number of CPUs - 1, expressed as $::processorcount - 1.
  # One instance is the minimum value and four instances is the maximum value.
  #
  # TODO: Determine if / where the default value for the 'jruby_max_active_instances' is set
  #   See https://tickets.puppetlabs.com/browse/SLV-530
  num_cores = output.to_i
  [[(num_cores - 1), MIN_DEFAULT_JRUBIES].max, MAX_DEFAULT_JRUBIES].min.to_s
end

# Returns the java args for the specified file
#
# @author Bill Claytor
#
# @param [String] file The file to search for java args
#
# @return [string] The java args
#
# @example
#   args = get_java_args(file)
#
# TODO: grep for java args
def get_java_args(file)
  path = if File.exist? "/etc/debian_version"
           "/etc/defaults/#{file}"
         else
           "/etc/sysconfig/#{file}"
         end

  value = if File.exist? path
            File.open(path).grep(/Xmx/)[0].split('"')[1]
          else
            NA
          end

  value
end

# Parses the specified java args into a hash with the following keys:
#  "Xms": the value for the 'Xms' parameter
#  "Xmx": the value for the 'Xmx' parameter
#  "Misc": the remaining args
#
# @author Bill Claytor
#
# @return [Hash] The parsed java args
#
# @example
#   result = parse_java_aggs(args)
#
def parse_java_aggs(args)
  xmx = args.match(/-Xmx\K[^\s]+/)
  xms = args.match(/-Xms\K[^\s]+/)
  misc = args.gsub("-Xmx#{xmx} ", "").gsub("-Xms#{xms} ", "")

  result = { "Xms" => xms, "Xmx" => xmx, "Misc" => misc }
  result
end

# Returns the value for the following setting:
# "puppet_enterprise::master::puppetserver::reserved_code_cache"
#
# Uses the 'ReservedCodeCacheSize' parameter in the 'pe-puppetserver' file
#
# @author Bill Claytor
#
# @return [string] The reserved_code_cache value
#
# @example
#   value = puppetserver_reserved_code_cache
#
#
def puppetserver_reserved_code_cache
  get_java_args("pe-puppetserver").match(/XX:ReservedCodeCacheSize=\K[^\s]+/) || NA
end

# Returns the value for the following setting:
# 'puppet_enterprise::profile::console::java_args'
#
# Uses the 'pe-console-services' file
#
# @author Bill Claytor
#
# @return [string] The java args
#
# @example
#   value = console_java_args
#
def console_java_args
  parse_java_aggs(get_java_args("pe-console-services"))
end

# Returns the value for the following setting:
# 'puppet_enterprise::profile::master::java_args'
#
# Uses the 'pe-puppetserver' file
#
# @author Bill Claytor
#
# @return [string] The java args
#
# @example
#   value = master_java_args
#
def master_java_args
  parse_java_aggs(get_java_args("pe-puppetserver"))
end

# Returns the value for the following setting:
# 'puppet_enterprise::profile::orchestrator::java_args'
#
# Uses the 'pe-orchestration-services' file
#
# @author Bill Claytor
#
# @return [string] The java args
#
# @example
#   value = zzz
#
def orchestrator_java_args
  parse_java_aggs(get_java_args("pe-orchestration-services"))
end

# Returns the value for the following setting:
# 'puppet_enterprise::profile::puppetdb::java_args'
#
# Uses the 'pe-puppetdb' file
#
# @author Bill Claytor
#
# @return [string] The java args
#
# @example
#   value = puppetdb_java_args
#
def puppetdb_java_args
  parse_java_aggs(get_java_args("pe-puppetdb"))
end

# Returns the value for the specified parameter in the specified config file
# Optionally accepts a list of exclusions to avoid collisions (i.e. 'work_mem' matching 'autovacuum_work_mem', etc)
# Works on the puppetdb and postgres conf files only.
#
# @author Bill Claytor
#
# @param [String] file The config file to search
# @param [String] parameter The parameter to search for
# @param [RegEx]  exclusions The regular expression used to exclude words from the search
#
# @return [string] The parameter value if found, otherwise "N/A"
#
# @example
#   value = get_conf_parameter(file, parameter)
#
def get_conf_parameter(file, parameter)
  return NA unless File.exist? file

  conf = File.read(file)
  match_pattern = /^\s*#{parameter} = (\S+)/
  conf_scan = conf.scan(match_pattern)
  conf_scan.last ? conf_scan.last.first : NA
end

# Returns the value for the specified parameter in the postgres config file
#
# @author Bill Claytor
#
# @param [String] parameter   The parameter to search for
#
# @return [string] The parameter value if found, otherwise "N/A"
#
# @example
#   value = get_postgres_parameter(parameter)
#
def get_postgres_parameter(parameter)
  get_conf_parameter(POSTGRES_CONF, parameter) unless POSTGRES_CONF.nil?
end

# Returns the value for the specified parameter in the puppetdb config file
#
# @author Bill Claytor
#
# @param [String] parameter   The parameter to search for
#
# @return [string] The parameter value if found, otherwise "N/A"
#
# @example
#   value = get_puppetdb_parameter(parameter)
#
def get_puppetdb_parameter(parameter)
  get_conf_parameter(PUPPET_DB_CONF, parameter)
end

# Returns the value for the following setting:
# 'puppet_enterprise::profile::database::shared_buffers'
#
# @author Bill Claytor
#
# @return [string] The value for the 'shared_buffers' parameter
#
# @example
#   value = database_shared_buffers
#
def database_shared_buffers
  get_postgres_parameter("shared_buffers")
end

# Returns the value for the following setting:
# 'puppet_enterprise::profile::database::autovacuum_max_workers'
#
# @author Bill Claytor
#
# @return [string] The value for the 'autovacuum_max_workers' parameter
#
# @example
#   value = database_autovacuum_max_workers
#
def database_autovacuum_max_workers
  get_postgres_parameter("autovacuum_max_workers")
end

# Returns the value for the following setting:
# 'puppet_enterprise::profile::database::autovacuum_work_mem'
#
# @author Bill Claytor
#
# @return [string] The value for the 'autovacuum_work_mem' parameter
#
# @example
#   value = database_autovacuum_work_mem
#
def database_autovacuum_work_mem
  get_postgres_parameter("autovacuum_work_mem")
end

# Returns the value for the following setting:
# 'puppet_enterprise::profile::database::maintenance_work_mem'
#
# @author Bill Claytor
#
# @return [string] The value for the 'maintenance_work_mem' parameter
#
# @example
#   value = database_maintenance_work_mem
#
def database_maintenance_work_mem
  get_postgres_parameter("maintenance_work_mem")
end

# Returns the value for the following setting:
# 'puppet_enterprise::profile::database::max_connections'
#
# @author Bill Claytor
#
# @return [string] The value for the 'max_connections' parameter
#
# @example
#   value = database_max_connections
#
def database_max_connections
  get_postgres_parameter("max_connections")
end

# Returns the value for the following setting:
# 'puppet_enterprise::profile::database::work_mem'
#
# @author Bill Claytor
#
# @return [string] The value for the 'work_mem' parameter
#
# @example
#   value = database_work_mem
#
def database_work_mem
  get_postgres_parameter("work_mem")
end

# Returns the value for the following setting:
# 'puppet_enterprise::puppetdb::command_processing_threads'
#
# @author Bill Claytor
#
# @return [string] The value for the 'threads' parameter
#
# @example
#   value = puppetdb_command_processing_threads
#
def puppetdb_command_processing_threads
  get_puppetdb_parameter("threads")
end

# Returns a JSON hash of the current values for the settings that can be adjusted using the 'pe_tune' module
# @author Bill Claytor
#
# @return [JSON] The current_settings hash
#
# @example
#   settings = current_settings
#
# rubocop:disable Metrics/LineLength
def current_settings
  params = {}
  params["puppet_enterprise::master::puppetserver::jruby_max_active_instances"] = puppetserver_jruby_max_active_instances
  params["puppet_enterprise::master::puppetserver::reserved_code_cache"] = puppetserver_reserved_code_cache
  params["puppet_enterprise::profile::console::java_args"] = console_java_args
  params["puppet_enterprise::profile::database::shared_buffers"] = database_shared_buffers
  params["puppet_enterprise::profile::database::autovacuum_max_workers"] = database_autovacuum_max_workers
  params["puppet_enterprise::profile::database::autovacuum_work_mem"] = database_autovacuum_work_mem
  params["puppet_enterprise::profile::database::maintenance_work_mem"] = database_maintenance_work_mem
  params["puppet_enterprise::profile::database::max_connections"] = database_max_connections
  params["puppet_enterprise::profile::database::work_mem"] = database_work_mem
  params["puppet_enterprise::profile::master::java_args"] = master_java_args
  params["puppet_enterprise::profile::orchestrator::java_args"] = orchestrator_java_args
  params["puppet_enterprise::profile::puppetdb::java_args"] = puppetdb_java_args
  params["puppet_enterprise::puppetdb::command_processing_threads"] = puppetdb_command_processing_threads

  settings_json = JSON.pretty_generate params

  # TODO: make this optional?
  puts settings_json

  # TODO: make the output location optional?
  FileUtils.mkdir_p DEFAULT_WORKING_DIRECTORY
  File.write("#{DEFAULT_WORKING_DIRECTORY}/#{DEFAULT_OUTPUT_FILE}", settings_json)

  settings_json
end

# rubocop:enable Metrics/LineLength

current_settings
