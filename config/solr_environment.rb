ENV['RAILS_ENV'] = (ENV['RAILS_ENV'] || 'development').dup

require "uri"
require "fileutils"
require "yaml"
require 'net/http'
require 'rails'

ACTS_AS_SOLR_ROOT = File.expand_path "#{File.dirname(__FILE__)}/.."
SOLR_BASE = Rails.root || ACTS_AS_SOLR_ROOT
SOLR_PATH = "#{SOLR_BASE}/solr" unless defined? SOLR_PATH
config = YAML::load_file "#{SOLR_BASE}/config/solr.yml"

unless defined? RAILS_ENV
  RAILS_ENV = ENV['RAILS_ENV']
end
unless defined? SOLR_LOGS_PATH
  SOLR_LOGS_PATH = ENV["SOLR_LOGS_PATH"] || "#{SOLR_BASE}/log"
end
unless defined? SOLR_PIDS_PATH
  SOLR_PIDS_PATH = ENV["SOLR_PIDS_PATH"] || "#{SOLR_BASE}/tmp/pids"
end
unless defined? SOLR_DATA_PATH
  SOLR_DATA_PATH = ENV["SOLR_DATA_PATH"] || config[ENV['RAILS_ENV']]['data_path'] || "#{SOLR_BASE}/solr/#{ENV['RAILS_ENV']}"
end
unless defined? SOLR_CONFIG_PATH
  SOLR_CONFIG_PATH = ENV["SOLR_CONFIG_PATH"] || "#{SOLR_PATH}/conf"
end
unless defined? SOLR_SERVER_PATH
  SOLR_SERVER_PATH = ENV["SOLR_CORE_PATH"] || "#{SOLR_PATH}/server"
end
unless defined? SOLR_PID_FILE
  SOLR_PID_FILE ="#{SOLR_PIDS_PATH}/solr.#{ENV['RAILS_ENV']}.pid"
end
unless defined? SOLR_CORE
  SOLR_CORE = ENV["SOLR_CORE"] || "default_core"
end

unless defined? SOLR_PORT
  raise("No solr environment defined for RAILS_ENV = #{ENV['RAILS_ENV'].inspect}") unless config[ENV['RAILS_ENV']]

  SOLR_HOST = ENV['HOST'] || URI.parse(config[ENV['RAILS_ENV']]['url']).host
  SOLR_PORT = ENV['PORT'] || URI.parse(config[ENV['RAILS_ENV']]['url']).port
end

SOLR_OPTIONS = config[ENV['RAILS_ENV']]['options'] unless defined? SOLR_OPTIONS

if ENV["RAILS_ENV"] == 'test'
  require "active_record"
  DB = (ENV['DB'] ? ENV['DB'] : 'sqlite') unless defined?(DB)
  MYSQL_USER = (ENV['MYSQL_USER'].nil? ? 'root' : ENV['MYSQL_USER']) unless defined? MYSQL_USER
  require File.join(File.dirname(File.expand_path(__FILE__)), '..', 'test', 'db', 'connections', DB, 'connection.rb')
end

